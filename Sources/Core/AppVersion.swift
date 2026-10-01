import Foundation

struct AppVersion: Equatable {
    let shortVersion: String
    let buildVersion: String

    init(shortVersion: String, buildVersion: String) {
        self.shortVersion = shortVersion
        self.buildVersion = buildVersion
    }

    init(bundle: Bundle = .main) {
        self.init(
            shortVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0",
            buildVersion: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0.0.0"
        )
    }

    static var current: AppVersion {
        AppVersion()
    }

    var displayText: String {
        if shortVersion == "0.0.0", buildVersion == "0.0.0" {
            "Version \(shortVersion) · Development build"
        } else {
            "Version \(shortVersion) · Personal local build"
        }
    }
}
