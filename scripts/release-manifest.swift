import CryptoKit
import Foundation

private struct CommandFailure: Error, CustomStringConvertible {
    let description: String
}

private func fail(_ message: String) throws -> Never {
    throw CommandFailure(description: message)
}

private struct Arguments {
    private var values: [String: [String]] = [:]

    init(_ raw: ArraySlice<String>) throws {
        var index = raw.startIndex
        while index < raw.endIndex {
            let option = raw[index]
            guard option.hasPrefix("--") else {
                try fail("unexpected argument: \(option)")
            }
            let valueIndex = raw.index(after: index)
            guard valueIndex < raw.endIndex else {
                try fail("\(option) requires a value")
            }
            values[option, default: []].append(raw[valueIndex])
            index = raw.index(after: valueIndex)
        }
    }

    func required(_ name: String) throws -> String {
        guard let matches = values[name], matches.count == 1, let value = matches.first, !value.isEmpty else {
            try fail("\(name) is required exactly once")
        }
        return value
    }

    func optional(_ name: String) throws -> String? {
        guard let matches = values[name] else { return nil }
        guard matches.count == 1 else {
            try fail("\(name) may be provided at most once")
        }
        return matches[0]
    }

    func all(_ name: String) -> [String] {
        values[name] ?? []
    }
}

private struct CommitRecord: Codable {
    let sha: String
    let classification: String
}

private struct VerificationRecord: Codable {
    let source: String
    let evidence: String
}

private struct SigningRecord: Codable {
    let certificateFingerprint: String
    let publicKeyFingerprint: String
}

private struct ArtifactRecord: Codable {
    let name: String
    let path: String
    let size: UInt64
    let sha256: String
}

private struct ReleaseManifest: Codable {
    let schemaVersion: Int
    let taskID: String
    let sourceSHA: String
    let baseTag: String?
    let baseSHA: String?
    let version: String
    let bootstrapPhase: String?
    let includedCommits: [CommitRecord]
    let verification: VerificationRecord
    let signing: SigningRecord
    let artifacts: [ArtifactRecord]
    let releaseNotes: String
    let stagingDirectory: String?
}

private let shaPattern = #"^[0-9a-f]{40}$"#
private let sha256Pattern = #"^[0-9a-f]{64}$"#
private let versionPattern = #"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$"#

private extension String {
    func matches(_ pattern: String) -> Bool {
        range(of: pattern, options: .regularExpression) != nil
    }
}

private func sha256(of data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func artifactRecord(stagingDirectory: URL, relativePath: String, name: String) throws -> ArtifactRecord {
    let file = try containedFile(stagingDirectory: stagingDirectory, relativePath: relativePath)
    let data = try Data(contentsOf: file)
    return ArtifactRecord(
        name: name,
        path: relativePath,
        size: UInt64(data.count),
        sha256: sha256(of: data)
    )
}

private func containedFile(stagingDirectory: URL, relativePath: String) throws -> URL {
    guard !relativePath.isEmpty, !relativePath.hasPrefix("/"),
          relativePath.split(separator: "/").allSatisfy({ $0 != ".." && $0 != "." }) else {
        try fail("artifact path must remain inside the staging directory")
    }
    let root = stagingDirectory.standardizedFileURL.resolvingSymlinksInPath()
    let candidate = root.appendingPathComponent(relativePath).standardizedFileURL.resolvingSymlinksInPath()
    let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
    guard candidate.path.hasPrefix(prefix), FileManager.default.fileExists(atPath: candidate.path) else {
        try fail("artifact path must remain inside the staging directory")
    }
    return candidate
}

private func validateShape(_ manifest: ReleaseManifest) throws {
    guard manifest.schemaVersion == 1,
          manifest.taskID.matches(#"^WH-M[0-9]+-[0-9]{3}$"#),
          manifest.sourceSHA.matches(shaPattern),
          manifest.version.matches(versionPattern),
          !manifest.includedCommits.isEmpty,
          !manifest.verification.source.isEmpty,
          !manifest.verification.evidence.isEmpty,
          manifest.signing.certificateFingerprint.matches(shaPattern),
          manifest.signing.publicKeyFingerprint.matches(sha256Pattern),
          !manifest.artifacts.isEmpty,
          !manifest.releaseNotes.isEmpty else {
        try fail("release manifest is incomplete or unsupported")
    }
    if let baseSHA = manifest.baseSHA, !baseSHA.matches(shaPattern) {
        try fail("release manifest is incomplete or unsupported")
    }
    guard (manifest.baseTag == nil) == (manifest.baseSHA == nil) else {
        try fail("release manifest is incomplete or unsupported")
    }
    if let baseTag = manifest.baseTag, !baseTag.matches(#"^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$"#) {
        try fail("release manifest is incomplete or unsupported")
    }
    if let phase = manifest.bootstrapPhase, !["initial", "update"].contains(phase) {
        try fail("release manifest is incomplete or unsupported")
    }
    if let stagingDirectory = manifest.stagingDirectory, !stagingDirectory.hasPrefix("/") {
        try fail("release manifest is incomplete or unsupported")
    }
    for artifact in manifest.artifacts {
        guard !artifact.path.isEmpty, !artifact.path.hasPrefix("/"),
              artifact.path.split(separator: "/").allSatisfy({ $0 != ".." && $0 != "." }) else {
            try fail("artifact path must remain inside the staging directory")
        }
    }
    let expectedArtifacts = [
        ("Whisper-\(manifest.version).zip", "artifacts/Whisper-\(manifest.version).zip"),
        ("appcast.xml", "artifacts/appcast.xml"),
    ]
    guard manifest.artifacts.count == expectedArtifacts.count,
          zip(manifest.artifacts, expectedArtifacts).allSatisfy({ artifact, expected in
              artifact.name == expected.0
                  && artifact.path == expected.1
                  && artifact.size > 0
                  && artifact.sha256.matches(sha256Pattern)
          }) else {
        try fail("release manifest is incomplete or unsupported")
    }
    guard Set(manifest.includedCommits.map(\.sha)).count == manifest.includedCommits.count else {
        try fail("release manifest is incomplete or unsupported")
    }
    for commit in manifest.includedCommits {
        guard commit.sha.matches(shaPattern), ["task", "closure"].contains(commit.classification) else {
            try fail("release manifest is incomplete or unsupported")
        }
    }
}

private func writeReleaseNotes(_ rawArguments: ArraySlice<String>) throws {
    let arguments = try Arguments(rawArguments)
    let manifest = try loadManifest(path: arguments.required("--manifest"))
    let output = URL(fileURLWithPath: try arguments.required("--output"))
    guard output.path.hasPrefix("/") else {
        try fail("release-notes output path must be absolute")
    }
    guard let data = manifest.releaseNotes.data(using: .utf8) else {
        try fail("release notes must be UTF-8")
    }
    try data.write(to: output, options: .atomic)
}

private func sanitizedManifest(_ manifest: ReleaseManifest) -> ReleaseManifest {
    ReleaseManifest(
        schemaVersion: manifest.schemaVersion,
        taskID: manifest.taskID,
        sourceSHA: manifest.sourceSHA,
        baseTag: manifest.baseTag,
        baseSHA: manifest.baseSHA,
        version: manifest.version,
        bootstrapPhase: manifest.bootstrapPhase,
        includedCommits: manifest.includedCommits,
        verification: manifest.verification,
        signing: manifest.signing,
        artifacts: manifest.artifacts,
        releaseNotes: manifest.releaseNotes,
        stagingDirectory: nil
    )
}

private func validatePublicManifest(_ rawArguments: ArraySlice<String>) throws {
    let arguments = try Arguments(rawArguments)
    let local = try loadManifest(path: arguments.required("--manifest"))
    let publicPath = try arguments.required("--public-manifest")
    let published = try loadManifest(path: publicPath)
    let publicData = try Data(contentsOf: URL(fileURLWithPath: publicPath))
    guard local.stagingDirectory != nil, published.stagingDirectory == nil,
          try encoder().encode(sanitizedManifest(local)) == publicData else {
        try fail("public manifest does not match the sanitized local manifest")
    }
}

private func verifyFileSignature(_ rawArguments: ArraySlice<String>) throws {
    let arguments = try Arguments(rawArguments)
    let fileData = try Data(contentsOf: URL(fileURLWithPath: arguments.required("--file")))
    let signatureData = try Data(contentsOf: URL(fileURLWithPath: arguments.required("--signature-file")))
    guard let signatureText = String(data: signatureData, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines),
        let signature = Data(base64Encoded: signatureText), signature.count == 64 else {
        try fail("prepared manifest signature is missing or malformed")
    }
    let publicKeyText = try arguments.required("--public-key")
    guard let publicKeyData = Data(base64Encoded: publicKeyText), publicKeyData.count == 32 else {
        try fail("configured public key is malformed")
    }
    let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
    guard publicKey.isValidSignature(signature, for: fileData) else {
        try fail("prepared manifest signature is invalid")
    }
}

private func decoder() -> JSONDecoder {
    JSONDecoder()
}

private func encoder() -> JSONEncoder {
    let value = JSONEncoder()
    value.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return value
}

private func loadManifest(path: String) throws -> ReleaseManifest {
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let manifest = try decoder().decode(ReleaseManifest.self, from: data)
        try validateShape(manifest)
        return manifest
    } catch let failure as CommandFailure {
        throw failure
    } catch {
        try fail("release manifest is incomplete or unsupported")
    }
}

private func writeManifests(_ rawArguments: ArraySlice<String>) throws {
    let arguments = try Arguments(rawArguments)
    let stagingPath = try arguments.required("--staging-dir")
    let stagingDirectory = URL(fileURLWithPath: stagingPath, isDirectory: true).standardizedFileURL
    guard stagingDirectory.path.hasPrefix("/") else {
        try fail("staging directory must be absolute")
    }
    let recordedStagingPath = try arguments.optional("--recorded-staging-dir") ?? stagingDirectory.path
    let recordedStagingDirectory = URL(
        fileURLWithPath: recordedStagingPath,
        isDirectory: true
    ).standardizedFileURL
    guard recordedStagingDirectory.path.hasPrefix("/") else {
        try fail("recorded staging directory must be absolute")
    }
    let taskID = try arguments.required("--task-id")
    let sourceSHA = try arguments.required("--source-sha")
    let baseTagValue = try arguments.required("--base-tag")
    let baseSHAValue = try arguments.required("--base-sha")
    let version = try arguments.required("--version")
    let bootstrapValue = try arguments.required("--bootstrap-phase")
    let verificationSource = try arguments.required("--verification-source")
    let verificationEvidence = try arguments.required("--verification-evidence")
    let signingFingerprint = try arguments.required("--signing-fingerprint").lowercased()
    let publicKeyFingerprint = try arguments.required("--public-key-fingerprint").lowercased()
    let zipRelative = try arguments.required("--zip-relative")
    let appcastRelative = try arguments.required("--appcast-relative")
    let notesRelative = try arguments.required("--release-notes-relative")

    let commits = try arguments.all("--commit").map { value -> CommitRecord in
        let pieces = value.split(separator: ":", maxSplits: 1).map(String.init)
        guard pieces.count == 2 else {
            try fail("--commit must use SHA:task or SHA:closure")
        }
        return CommitRecord(sha: pieces[0], classification: pieces[1])
    }
    let notesURL = try containedFile(stagingDirectory: stagingDirectory, relativePath: notesRelative)
    guard let notes = String(data: try Data(contentsOf: notesURL), encoding: .utf8), !notes.isEmpty else {
        try fail("release notes must be non-empty UTF-8")
    }
    let artifacts = try [
        artifactRecord(stagingDirectory: stagingDirectory, relativePath: zipRelative, name: "Whisper-\(version).zip"),
        artifactRecord(stagingDirectory: stagingDirectory, relativePath: appcastRelative, name: "appcast.xml"),
    ]
    let baseTag = baseTagValue == "none" ? nil : baseTagValue
    let baseSHA = baseSHAValue == "none" ? nil : baseSHAValue
    let bootstrapPhase = bootstrapValue == "none" ? nil : bootstrapValue
    let common = ReleaseManifest(
        schemaVersion: 1,
        taskID: taskID,
        sourceSHA: sourceSHA,
        baseTag: baseTag,
        baseSHA: baseSHA,
        version: version,
        bootstrapPhase: bootstrapPhase,
        includedCommits: commits,
        verification: VerificationRecord(source: verificationSource, evidence: verificationEvidence),
        signing: SigningRecord(
            certificateFingerprint: signingFingerprint,
            publicKeyFingerprint: publicKeyFingerprint
        ),
        artifacts: artifacts,
        releaseNotes: notes,
        stagingDirectory: recordedStagingDirectory.path
    )
    try validateShape(common)

    let localURL = stagingDirectory.appendingPathComponent("release-manifest.local.json")
    let publicURL = stagingDirectory.appendingPathComponent("artifacts/release-manifest.json")
    let publicManifest = sanitizedManifest(common)
    try FileManager.default.createDirectory(at: publicURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try encoder().encode(common).write(to: localURL, options: .atomic)
    try encoder().encode(publicManifest).write(to: publicURL, options: .atomic)
}

private func validateManifest(_ rawArguments: ArraySlice<String>) throws {
    let arguments = try Arguments(rawArguments)
    let manifestPath = try arguments.required("--manifest")
    let stagingPath = try arguments.required("--staging-dir")
    let signingFingerprint = try arguments.required("--signing-fingerprint").lowercased()
    let publicKeyFingerprint = try arguments.required("--public-key-fingerprint").lowercased()
    let root = URL(fileURLWithPath: stagingPath, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
    let manifest = try loadManifest(path: manifestPath)
    guard manifest.stagingDirectory == root.path else {
        try fail("manifest staging directory does not match the requested staging directory")
    }
    guard manifest.signing.certificateFingerprint == signingFingerprint else {
        try fail("signing identity fingerprint changed")
    }
    guard manifest.signing.publicKeyFingerprint == publicKeyFingerprint else {
        try fail("update public-key fingerprint changed")
    }
    for artifact in manifest.artifacts {
        let file = try containedFile(stagingDirectory: root, relativePath: artifact.path)
        let data = try Data(contentsOf: file)
        guard UInt64(data.count) == artifact.size, sha256(of: data) == artifact.sha256 else {
            try fail("artifact digest or size changed: \(artifact.name)")
        }
    }
}

private func readField(_ rawArguments: ArraySlice<String>) throws {
    let arguments = try Arguments(rawArguments)
    let manifest = try loadManifest(path: arguments.required("--manifest"))
    switch try arguments.required("--name") {
    case "taskID": print(manifest.taskID)
    case "sourceSHA": print(manifest.sourceSHA)
    case "baseTag": print(manifest.baseTag ?? "")
    case "baseSHA": print(manifest.baseSHA ?? "")
    case "version": print(manifest.version)
    case "bootstrapPhase": print(manifest.bootstrapPhase ?? "")
    case "stagingDirectory": print(manifest.stagingDirectory ?? "")
    case "releaseNotes": print(manifest.releaseNotes)
    case "commitRecords":
        for commit in manifest.includedCommits {
            print("\(commit.sha):\(commit.classification)")
        }
    default: try fail("unsupported manifest field")
    }
}

private final class AppcastParser: NSObject, XMLParserDelegate {
    var enclosure: [String: String]?
    var enclosureCount = 0
    var version: String?
    var shortVersion: String?
    var releaseNotesLinkCount = 0
    var itemCount = 0
    var parserError: Error?
    private var capturedElement: String?
    private var capturedText = ""
    private var depth = 0
    private var itemDepth: Int?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        depth += 1
        if elementName == "item" {
            itemCount += 1
            if itemDepth == nil {
                itemDepth = depth
            }
            return
        }
        guard let itemDepth, depth == itemDepth + 1 else { return }
        if elementName == "enclosure" {
            enclosureCount += 1
            if enclosure == nil {
                enclosure = attributeDict
            }
        } else if elementName == "sparkle:version" || elementName == "sparkle:shortVersionString" {
            capturedElement = elementName
            capturedText = ""
        } else if elementName == "sparkle:releaseNotesLink" {
            releaseNotesLinkCount += 1
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturedElement != nil {
            capturedText += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == capturedElement {
            let value = capturedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if elementName == "sparkle:version" {
                version = value
            } else {
                shortVersion = value
            }
            capturedElement = nil
            capturedText = ""
        }
        if elementName == "item", depth == itemDepth {
            itemDepth = nil
        }
        depth -= 1
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        parserError = parseError
    }
}

private func loadBundlePlist(at path: String) throws -> [String: Any] {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
        try fail("bundle Info.plist is malformed")
    }
    return plist
}

private func verifyFeedArtifacts(
    appcastPath: String,
    archivePath: String,
    publicKeyText: String,
    version: String
) throws {
    guard version.matches(versionPattern) else {
        try fail("release version must be MAJOR.MINOR.PATCH")
    }

    let appcastData = try Data(contentsOf: URL(fileURLWithPath: appcastPath))
    let parser = XMLParser(data: appcastData)
    let delegate = AppcastParser()
    parser.delegate = delegate
    guard parser.parse(), delegate.parserError == nil, delegate.itemCount == 1,
          delegate.enclosureCount == 1,
          delegate.releaseNotesLinkCount == 0, let enclosure = delegate.enclosure else {
        try fail("appcast XML is malformed")
    }

    let expectedURL = "https://github.com/yurybv/whisper/releases/download/v\(version)/Whisper-\(version).zip"
    guard enclosure["url"] == expectedURL else {
        try fail("unexpected enclosure URL")
    }
    guard delegate.version == version, delegate.shortVersion == version else {
        try fail("feed versions do not match the release")
    }
    guard let signatureText = enclosure["sparkle:edSignature"],
          let signature = Data(base64Encoded: signatureText), signature.count == 64 else {
        try fail("feed EdDSA signature is missing or malformed")
    }
    guard let publicKeyData = Data(base64Encoded: publicKeyText), publicKeyData.count == 32 else {
        try fail("configured public key is malformed")
    }

    let archiveData = try Data(contentsOf: URL(fileURLWithPath: archivePath))
    let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
    guard publicKey.isValidSignature(signature, for: archiveData) else {
        try fail("EdDSA signature verification failed")
    }

    guard let lengthText = enclosure["length"], let feedLength = UInt64(lengthText) else {
        try fail("enclosure length is missing or malformed")
    }
    guard feedLength == UInt64(archiveData.count) else {
        try fail("enclosure length does not match the archive")
    }
}

private func verifyFeed(_ rawArguments: ArraySlice<String>) throws {
    let arguments = try Arguments(rawArguments)
    let appcastPath = try arguments.required("--appcast")
    let archivePath = try arguments.required("--archive")
    let bundlePlistPath = try arguments.required("--bundle-plist")
    let publicKeyText = try arguments.required("--public-key")
    let version = try arguments.required("--version")

    let plist = try loadBundlePlist(at: bundlePlistPath)
    guard plist["CFBundleIdentifier"] as? String == "dev.yury.whisper" else {
        try fail("bundle identifier does not match dev.yury.whisper")
    }
    guard plist["CFBundleShortVersionString"] as? String == version,
          plist["CFBundleVersion"] as? String == version else {
        try fail("bundle versions do not match the release")
    }
    guard plist["SUFeedURL"] as? String == "https://github.com/yurybv/whisper/releases/latest/download/appcast.xml" else {
        try fail("bundle update feed URL is unexpected")
    }
    guard plist["SUPublicEDKey"] as? String == publicKeyText else {
        try fail("configured public key does not match the bundle")
    }
    try verifyFeedArtifacts(
        appcastPath: appcastPath,
        archivePath: archivePath,
        publicKeyText: publicKeyText,
        version: version
    )
}

private func verifyFeedArtifacts(_ rawArguments: ArraySlice<String>) throws {
    let arguments = try Arguments(rawArguments)
    try verifyFeedArtifacts(
        appcastPath: arguments.required("--appcast"),
        archivePath: arguments.required("--archive"),
        publicKeyText: arguments.required("--public-key"),
        version: arguments.required("--version")
    )
}

private func fingerprintPublicKey(_ rawArguments: ArraySlice<String>) throws {
    let arguments = try Arguments(rawArguments)
    let publicKeyText = try arguments.required("--public-key")
    guard let publicKeyData = Data(base64Encoded: publicKeyText), publicKeyData.count == 32 else {
        try fail("configured public key is malformed")
    }
    print(sha256(of: publicKeyData))
}

private func run() throws {
    guard CommandLine.arguments.count >= 2 else {
        try fail("a release manifest command is required")
    }
    let command = CommandLine.arguments[1]
    let arguments = CommandLine.arguments.dropFirst(2)
    switch command {
    case "fingerprint-public-key":
        try fingerprintPublicKey(arguments)
    case "write":
        try writeManifests(arguments)
    case "validate":
        try validateManifest(arguments)
    case "field":
        try readField(arguments)
    case "write-release-notes":
        try writeReleaseNotes(arguments)
    case "validate-public":
        try validatePublicManifest(arguments)
    case "verify-file-signature":
        try verifyFileSignature(arguments)
    case "verify-feed":
        try verifyFeed(arguments)
    case "verify-feed-artifacts":
        try verifyFeedArtifacts(arguments)
    default:
        try fail("unknown release manifest command: \(command)")
    }
}

do {
    try run()
} catch let error as CommandFailure {
    fputs("error: \(error.description)\n", stderr)
    exit(1)
} catch {
    fputs("error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
