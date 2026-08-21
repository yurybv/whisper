import Foundation

struct MultipartFormData: Sendable {
    let boundary: String
    private var parts: [Data] = []

    init(boundary: String = "Whisper-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    var contentType: String {
        "multipart/form-data; boundary=\(boundary)"
    }

    mutating func appendField(name: String, value: String) {
        var part = Data()
        part.appendUTF8("--\(boundary)\r\n")
        part.appendUTF8(
            "Content-Disposition: form-data; name=\"\(Self.escapeDispositionValue(name))\"\r\n\r\n"
        )
        part.appendUTF8(value)
        part.appendUTF8("\r\n")
        parts.append(part)
    }

    mutating func appendFile(
        name: String,
        filename: String,
        mimeType: String,
        data: Data
    ) {
        var part = Data()
        part.appendUTF8("--\(boundary)\r\n")
        part.appendUTF8(
            "Content-Disposition: form-data; name=\"\(Self.escapeDispositionValue(name))\"; "
                + "filename=\"\(Self.escapeDispositionValue(filename))\"\r\n"
        )
        part.appendUTF8("Content-Type: \(mimeType)\r\n\r\n")
        part.append(data)
        part.appendUTF8("\r\n")
        parts.append(part)
    }

    func encoded() -> Data {
        var data = Data()
        for part in parts {
            data.append(part)
        }
        data.appendUTF8("--\(boundary)--\r\n")
        return data
    }

    private static func escapeDispositionValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r", with: "_")
            .replacingOccurrences(of: "\n", with: "_")
            .replacingOccurrences(of: "\"", with: "%22")
    }
}

private extension Data {
    mutating func appendUTF8(_ value: String) {
        append(contentsOf: value.utf8)
    }
}
