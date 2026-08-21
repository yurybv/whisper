import XCTest
@testable import Whisper

final class MultipartFormDataTests: XCTestCase {
    func testEncodesFieldsAndFileWithCRLFAndClosingBoundary() {
        var form = MultipartFormData(boundary: "WhisperBoundary")
        form.appendField(name: "model", value: "gpt-transcribe")
        form.appendFile(
            name: "file",
            filename: "sample.wav",
            mimeType: "audio/wav",
            data: Data("audio-bytes".utf8)
        )

        let body = String(decoding: form.encoded(), as: UTF8.self)

        XCTAssertEqual(form.contentType, "multipart/form-data; boundary=WhisperBoundary")
        XCTAssertTrue(body.contains("--WhisperBoundary\r\n"))
        XCTAssertTrue(body.contains("Content-Disposition: form-data; name=\"model\"\r\n\r\ngpt-transcribe\r\n"))
        XCTAssertTrue(body.contains("Content-Disposition: form-data; name=\"file\"; filename=\"sample.wav\"\r\n"))
        XCTAssertTrue(body.contains("Content-Type: audio/wav\r\n\r\naudio-bytes\r\n"))
        XCTAssertTrue(body.hasSuffix("--WhisperBoundary--\r\n"))
    }

    func testDefaultBoundaryIsNonEmptyAndChangesBetweenForms() {
        let first = MultipartFormData()
        let second = MultipartFormData()

        XCTAssertFalse(first.boundary.isEmpty)
        XCTAssertNotEqual(first.boundary, second.boundary)
    }
}
