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
