import Foundation
import XCTest
@testable import Whisper

final class DictationErrorPresentationTests: XCTestCase {
    func testMissingOrInvalidKeyExplainsSettingsAndRetainedRetry() {
        let message = DictationErrorPresentation.message(
            for: FeatureError.invalidAPIKey,
            recovery: .retryOrDiscard
        )

        XCTAssertTrue(message.contains("Settings"))
        XCTAssertTrue(message.contains("Retry"))
    }

    func testOfflineFailureExplainsNetworkAndRetainedRetry() {
        let message = DictationErrorPresentation.message(
            for: URLError(.notConnectedToInternet),
            recovery: .retryOrDiscard
        )

        XCTAssertTrue(message.contains("network"))
        XCTAssertTrue(message.contains("Retry"))
    }

    func testProviderMessageCannotLeakAuthorizationOrCredentialText() {
        let message = DictationErrorPresentation.message(
            for: OpenAIClientError.api(message: "Authorization Bearer sk-unit-test-secret"),
            recovery: .retryOrDiscard
        )

        XCTAssertFalse(message.contains("Authorization"))
        XCTAssertFalse(message.contains("sk-unit-test-secret"))
    }

    func testMicrophoneFailureHasActionableMessageWithoutRetryClaim() {
        let message = DictationErrorPresentation.message(
            for: FeatureError.microphoneDisconnected,
            recovery: .none
        )

        XCTAssertTrue(message.contains("microphone"))
        XCTAssertFalse(message.contains("Retry"))
    }

    func testUnknownErrorCannotExposeItsRawDescription() {
        let message = DictationErrorPresentation.message(
            for: NSError(
                domain: "test",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "private credential-token"]
            ),
            recovery: .retryOrDiscard
        )

        XCTAssertFalse(message.contains("credential-token"))
        XCTAssertTrue(message.contains("Retry"))
    }

    func testDiscardOnlyFailureDoesNotOfferRetry() {
        let message = DictationErrorPresentation.message(
            for: OpenAIClientError.uploadTooLarge(maximumBytes: 3),
            recovery: .discardOnly
        )

        XCTAssertTrue(message.contains("Discard"))
        XCTAssertFalse(message.contains("Retry"))
    }
}
