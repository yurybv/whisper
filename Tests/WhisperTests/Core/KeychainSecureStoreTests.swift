import LocalAuthentication
import Security
import XCTest
@testable import Whisper

final class KeychainSecureStoreTests: XCTestCase {
    func testSavesReplacesReadsAndDeletesKey() throws {
        let store = KeychainSecureStore(
            service: "dev.yury.whisper.tests.\(UUID().uuidString)"
        )
        defer { try? store.deleteOpenAIKey() }

        XCTAssertFalse(try store.containsOpenAIKey())
        XCTAssertNil(try store.readOpenAIKey())

        try store.saveOpenAIKey("first-test-value")
        XCTAssertTrue(try store.containsOpenAIKey())
        XCTAssertEqual(try store.readOpenAIKey(), "first-test-value")

        try store.saveOpenAIKey("replacement-test-value")
        XCTAssertEqual(try store.readOpenAIKey(), "replacement-test-value")

        try store.deleteOpenAIKey()
        XCTAssertFalse(try store.containsOpenAIKey())
        XCTAssertNil(try store.readOpenAIKey())
    }

    func testInMemoryStoreSupportsTheSameLifecycle() throws {
        let store: any SecureStore = InMemorySecureStore()

        XCTAssertFalse(try store.containsOpenAIKey())
        try store.saveOpenAIKey("temporary-test-value")
        XCTAssertTrue(try store.containsOpenAIKey())
        XCTAssertEqual(try store.readOpenAIKey(), "temporary-test-value")

        try store.deleteOpenAIKey()
        XCTAssertFalse(try store.containsOpenAIKey())
        XCTAssertNil(try store.readOpenAIKey())
    }

    func testKeychainAutomaticQueriesDisableAuthenticationUI() {
        let store = KeychainSecureStore(service: "dev.yury.whisper.tests.query")

        let presenceQuery = store.presenceQuery
        XCTAssertEqual(presenceQuery[kSecReturnAttributes] as? Bool, true)
        XCTAssertNil(presenceQuery[kSecReturnData])
        XCTAssertEqual(
            (presenceQuery[kSecUseAuthenticationContext] as? LAContext)?.interactionNotAllowed,
            true
        )

        let readQuery = store.readQuery
        XCTAssertEqual(readQuery[kSecReturnData] as? Bool, true)
        XCTAssertNil(readQuery[kSecReturnAttributes])
        XCTAssertEqual(
            (readQuery[kSecUseAuthenticationContext] as? LAContext)?.interactionNotAllowed,
            true
        )
    }

    func testAutomaticOperationTemporarilyDisablesLegacyKeychainInteraction() {
        var interactionWasAllowed = DarwinBoolean(false)
        XCTAssertEqual(
            SecKeychainGetUserInteractionAllowed(&interactionWasAllowed),
            errSecSuccess
        )

        for operationStatus in [errSecSuccess, errSecAuthFailed] {
            let status = KeychainSecureStore.performWithoutUserInteraction {
                var interactionIsAllowed = DarwinBoolean(true)
                guard SecKeychainGetUserInteractionAllowed(&interactionIsAllowed) == errSecSuccess else {
                    return errSecInternalError
                }
                return interactionIsAllowed.boolValue
                    ? errSecInteractionNotAllowed
                    : operationStatus
            }

            XCTAssertEqual(status, operationStatus)
            var interactionIsAllowedAfterward = DarwinBoolean(false)
            XCTAssertEqual(
                SecKeychainGetUserInteractionAllowed(&interactionIsAllowedAfterward),
                errSecSuccess
            )
            XCTAssertEqual(interactionIsAllowedAfterward.boolValue, interactionWasAllowed.boolValue)
        }
    }

    func testCachingStoreReadsAStoredKeyFromItsBackingStoreOnlyOnce() throws {
        let backingStore = CountingSecureStore(value: "session-test-value")
        let store = CachingSecureStore(backingStore: backingStore)

        XCTAssertEqual(try store.readOpenAIKey(), "session-test-value")
        XCTAssertEqual(try store.readOpenAIKey(), "session-test-value")
        XCTAssertEqual(backingStore.readCount, 1)
    }

    func testCachingStoreChecksBackingPresenceWithoutReadingOrCachingSecret() throws {
        let backingStore = CountingSecureStore(value: "session-test-value")
        let store = CachingSecureStore(backingStore: backingStore)

        XCTAssertTrue(try store.containsOpenAIKey())
        XCTAssertTrue(try store.containsOpenAIKey())
        XCTAssertEqual(backingStore.presenceCount, 2)
        XCTAssertEqual(backingStore.readCount, 0)

        XCTAssertEqual(try store.readOpenAIKey(), "session-test-value")
        XCTAssertEqual(backingStore.readCount, 1)
    }

    func testCachingStoreUsesCachedNonemptyKeyForPresence() throws {
        let backingStore = CountingSecureStore(value: "session-test-value")
        let store = CachingSecureStore(backingStore: backingStore)

        XCTAssertEqual(try store.readOpenAIKey(), "session-test-value")
        XCTAssertTrue(try store.containsOpenAIKey())

        XCTAssertEqual(backingStore.readCount, 1)
        XCTAssertEqual(backingStore.presenceCount, 0)
    }

    func testCachingStoreDoesNotCacheAMissingKeyOrReadFailure() throws {
        let backingStore = CountingSecureStore(value: nil)
        let store = CachingSecureStore(backingStore: backingStore)

        XCTAssertNil(try store.readOpenAIKey())
        backingStore.setReadError(TestSecureStoreError.readFailed)
        XCTAssertThrowsError(try store.readOpenAIKey())
        backingStore.setReadError(nil)
        backingStore.setValue("available-later")

        XCTAssertEqual(try store.readOpenAIKey(), "available-later")
        XCTAssertEqual(backingStore.readCount, 3)
    }

    func testCachingStoreDoesNotCacheAWhitespaceOnlyKey() throws {
        let backingStore = CountingSecureStore(value: "  \n")
        let store = CachingSecureStore(backingStore: backingStore)

        XCTAssertEqual(try store.readOpenAIKey(), "  \n")
        XCTAssertEqual(try store.readOpenAIKey(), "  \n")
        XCTAssertEqual(backingStore.readCount, 2)
    }

    func testCachingStoreSerializesConcurrentInitialReads() {
        let backingStore = CountingSecureStore(
            value: "concurrent-value",
            readDelay: 0.02
        )
        let store = CachingSecureStore(backingStore: backingStore)
        let results = ConcurrentReadResults()

        DispatchQueue.concurrentPerform(iterations: 16) { _ in
            results.record(Result { try store.readOpenAIKey() })
        }

        let snapshot = results.snapshot()
        XCTAssertEqual(snapshot.errors, 0)
        XCTAssertEqual(snapshot.values.count, 16)
        XCTAssertTrue(snapshot.values.allSatisfy { $0 == "concurrent-value" })
        XCTAssertEqual(backingStore.readCount, 1)
    }

    func testCachingStoreUpdatesItsCacheAfterSaving() throws {
        let backingStore = CountingSecureStore(value: "old-value")
        let store = CachingSecureStore(backingStore: backingStore)

        XCTAssertEqual(try store.readOpenAIKey(), "old-value")
        try store.saveOpenAIKey("new-value")

        XCTAssertEqual(try store.readOpenAIKey(), "new-value")
        XCTAssertEqual(backingStore.readCount, 1)
    }

    func testCachingStoreClearsItsCacheAfterDeleting() throws {
        let backingStore = CountingSecureStore(value: "saved-value")
        let store = CachingSecureStore(backingStore: backingStore)

        XCTAssertEqual(try store.readOpenAIKey(), "saved-value")
        try store.deleteOpenAIKey()

        XCTAssertNil(try store.readOpenAIKey())
        XCTAssertEqual(backingStore.readCount, 2)
    }
}

private enum TestSecureStoreError: Error {
    case readFailed
}

private final class CountingSecureStore: SecureStore, @unchecked Sendable {
    private let lock = NSLock()
    private let readDelay: TimeInterval
    private var value: String?
    private var readError: Error?
    private var storedReadCount = 0
    private var storedPresenceCount = 0

    init(value: String?, readDelay: TimeInterval = 0) {
        self.value = value
        self.readDelay = readDelay
    }

    var readCount: Int {
        lock.withLock { storedReadCount }
    }

    var presenceCount: Int {
        lock.withLock { storedPresenceCount }
    }

    func setValue(_ value: String?) {
        lock.withLock {
            self.value = value
        }
    }

    func setReadError(_ error: Error?) {
        lock.withLock {
            readError = error
        }
    }

    func readOpenAIKey() throws -> String? {
        try lock.withLock {
            storedReadCount += 1
            if readDelay > 0 {
                Thread.sleep(forTimeInterval: readDelay)
            }
            if let readError {
                throw readError
            }
            return value
        }
    }

    func containsOpenAIKey() -> Bool {
        lock.withLock {
            storedPresenceCount += 1
            return value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
    }

    func saveOpenAIKey(_ value: String) throws {
        lock.withLock {
            self.value = value
        }
    }

    func deleteOpenAIKey() throws {
        lock.withLock {
            value = nil
        }
    }
}

private final class ConcurrentReadResults: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String?] = []
    private var errors = 0

    func record(_ result: Result<String?, Error>) {
        lock.withLock {
            switch result {
            case let .success(value):
                values.append(value)
            case .failure:
                errors += 1
            }
        }
    }

    func snapshot() -> (values: [String?], errors: Int) {
        lock.withLock { (values, errors) }
    }
}
