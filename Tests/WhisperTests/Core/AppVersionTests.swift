import XCTest
@testable import Whisper

final class AppVersionTests: XCTestCase {
    func testDevelopmentBundleUsesAnExplicitDevelopmentLabel() {
        let version = AppVersion(shortVersion: "0.0.0", buildVersion: "0.0.0")

        XCTAssertEqual(version.displayText, "Version 0.0.0 · Development build")
    }

    func testInstalledReleaseDisplaysItsBundleVersion() {
        let version = AppVersion(shortVersion: "1.0.0", buildVersion: "1.0.0")

        XCTAssertEqual(version.displayText, "Version 1.0.0 · Personal local build")
    }

    func testBundleVersionUsesMatchingShortAndBuildVersions() {
        let version = AppVersion(shortVersion: "1.0.0", buildVersion: "1.0.0")

        XCTAssertEqual(version.shortVersion, version.buildVersion)
    }
}
