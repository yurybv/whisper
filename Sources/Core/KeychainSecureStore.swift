import Foundation
import LocalAuthentication
import Security

struct KeychainSecureStore: SecureStore {
    static let defaultService = "dev.yury.whisper.openai"
    static let defaultAccount = "api-key"
    private static let operationLock = NSLock()

    let service: String
    let account: String

    init(
        service: String = Self.defaultService,
        account: String = Self.defaultAccount
    ) {
        self.service = service
        self.account = account
    }

    func containsOpenAIKey() throws -> Bool {
        let status = Self.performWithoutUserInteraction {
            SecItemCopyMatching(presenceQuery as CFDictionary, nil)
        }
        switch status {
        case errSecSuccess:
            return true
        case errSecItemNotFound:
            return false
        default:
            throw FeatureError.keychain
        }
    }

    func readOpenAIKey() throws -> String? {
        var result: CFTypeRef?
        let status = Self.performWithoutUserInteraction {
            SecItemCopyMatching(readQuery as CFDictionary, &result)
        }
        if status == errSecItemNotFound {
            return nil
        }
        guard
            status == errSecSuccess,
            let data = result as? Data,
            let value = String(data: data, encoding: .utf8)
        else {
            throw FeatureError.keychain
        }
        return value
    }

    func saveOpenAIKey(_ value: String) throws {
        try Self.performSerialized {
            let data = Data(value.utf8)
            let updateStatus = SecItemUpdate(
                itemQuery as CFDictionary,
                [kSecValueData: data] as CFDictionary
            )

            if updateStatus == errSecItemNotFound {
                var attributes = itemQuery
                attributes[kSecValueData] = data
                attributes[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else {
                    throw FeatureError.keychain
                }
                return
            }

            guard updateStatus == errSecSuccess else {
                throw FeatureError.keychain
            }
        }
    }

    func deleteOpenAIKey() throws {
        try Self.performSerialized {
            let status = SecItemDelete(itemQuery as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw FeatureError.keychain
            }
        }
    }

    private var itemQuery: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
    }

    var presenceQuery: [CFString: Any] {
        var query = itemQuery
        query[kSecReturnAttributes] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext] = Self.noninteractiveContext()
        return query
    }

    var readQuery: [CFString: Any] {
        var query = itemQuery
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext] = Self.noninteractiveContext()
        return query
    }

    static func performWithoutUserInteraction(_ operation: () -> OSStatus) -> OSStatus {
        performSerialized {
            var interactionWasAllowed = DarwinBoolean(false)
            guard
                SecKeychainGetUserInteractionAllowed(&interactionWasAllowed) == errSecSuccess,
                SecKeychainSetUserInteractionAllowed(false) == errSecSuccess
            else {
                return errSecInteractionNotAllowed
            }
            defer {
                _ = SecKeychainSetUserInteractionAllowed(interactionWasAllowed.boolValue)
            }
            return operation()
        }
    }

    private static func performSerialized<T>(_ operation: () throws -> T) rethrows -> T {
        operationLock.lock()
        defer { operationLock.unlock() }
        return try operation()
    }

    private static func noninteractiveContext() -> LAContext {
        let context = LAContext()
        context.interactionNotAllowed = true
        return context
    }
}
