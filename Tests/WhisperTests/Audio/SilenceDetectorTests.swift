import XCTest
@testable import Whisper

final class SilenceDetectorTests: XCTestCase {
    private let detector = SilenceDetector(minimumDuration: 0.25, speechThreshold: 0.02)

    func testRecordingShorterThanMinimumDoesNotContainSpeech() {
        XCTAssertFalse(detector.containsSpeech(duration: 0.249, peakLevel: 1))
    }

    func testRecordingBelowThresholdDoesNotContainSpeech() {
        XCTAssertFalse(detector.containsSpeech(duration: 1, peakLevel: 0.019))
    }

    func testRecordingAtBothBoundariesContainsSpeech() {
        XCTAssertTrue(detector.containsSpeech(duration: 0.25, peakLevel: 0.02))
    }
}
