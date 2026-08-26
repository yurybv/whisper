import Foundation

protocol SecureStore: Sendable {
    func readOpenAIKey() throws -> String?
    func saveOpenAIKey(_ value: String) throws
    func deleteOpenAIKey() throws
}

final class InMemorySecureStore: SecureStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?

    func readOpenAIKey() -> String? {
        lock.withLock { value }
    }

    func saveOpenAIKey(_ value: String) {
        lock.withLock {
            self.value = value
        }
    }

    func deleteOpenAIKey() {
        lock.withLock {
            value = nil
        }
    }
}

final class CachingSecureStore: SecureStore, @unchecked Sendable {
    private let lock = NSLock()
    private let backingStore: any SecureStore
    private var cachedKey: String?

    init(backingStore: any SecureStore) {
        self.backingStore = backingStore
    }

    func readOpenAIKey() throws -> String? {
        try lock.withLock {
            if let cachedKey {
                return cachedKey
            }

            let key = try backingStore.readOpenAIKey()
            if let key, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                cachedKey = key
            }
            return key
        }
    }

    func saveOpenAIKey(_ value: String) throws {
        try lock.withLock {
            try backingStore.saveOpenAIKey(value)
            cachedKey = value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : value
        }
    }

    func deleteOpenAIKey() throws {
        try lock.withLock {
            try backingStore.deleteOpenAIKey()
            cachedKey = nil
        }
    }
}
