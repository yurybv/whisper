import XCTest
@testable import Whisper

final class SmokeTests: XCTestCase {
    private var applicationBundle: Bundle {
        Bundle(for: AppDelegate.self)
    }

    func testApplicationBundleIdentifier() {
        XCTAssertEqual(applicationBundle.bundleIdentifier, "dev.yury.whisper")
    }

    func testApplicationRunsAsMenuBarUtility() {
        XCTAssertEqual(applicationBundle.object(forInfoDictionaryKey: "LSUIElement") as? Bool, true)
    }

    func testApplicationDeclaresRecordingPermissions() {
        XCTAssertNotNil(applicationBundle.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") as? String)
        XCTAssertNotNil(applicationBundle.object(forInfoDictionaryKey: "NSScreenCaptureUsageDescription") as? String)
    }
}
