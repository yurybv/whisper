import Foundation
import Security

struct KeychainSecureStore: SecureStore {
    static let defaultService = "dev.yury.whisper.openai"
    static let defaultAccount = "api-key"

    let service: String
    let account: String

    init(
        service: String = Self.defaultService,
        account: String = Self.defaultAccount
    ) {
        self.service = service
        self.account = account
    }

    func readOpenAIKey() throws -> String? {
        var query = itemQuery
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
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

    func deleteOpenAIKey() throws {
        let status = SecItemDelete(itemQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw FeatureError.keychain
        }
    }

    private var itemQuery: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
    }
}
