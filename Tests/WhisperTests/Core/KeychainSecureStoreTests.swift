import XCTest
@testable import Whisper

final class KeychainSecureStoreTests: XCTestCase {
    func testSavesReplacesReadsAndDeletesKey() throws {
        let store = KeychainSecureStore(
            service: "dev.yury.whisper.tests.\(UUID().uuidString)"
        )
        defer { try? store.deleteOpenAIKey() }

        XCTAssertNil(try store.readOpenAIKey())

        try store.saveOpenAIKey("first-test-value")
        XCTAssertEqual(try store.readOpenAIKey(), "first-test-value")

        try store.saveOpenAIKey("replacement-test-value")
        XCTAssertEqual(try store.readOpenAIKey(), "replacement-test-value")

        try store.deleteOpenAIKey()
        XCTAssertNil(try store.readOpenAIKey())
    }

    func testInMemoryStoreSupportsTheSameLifecycle() throws {
        let store: any SecureStore = InMemorySecureStore()

        try store.saveOpenAIKey("temporary-test-value")
        XCTAssertEqual(try store.readOpenAIKey(), "temporary-test-value")

        try store.deleteOpenAIKey()
        XCTAssertNil(try store.readOpenAIKey())
    }
}
