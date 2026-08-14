import Foundation
import Security

enum KeychainStoreFailure: Error, Equatable {
    case unexpectedStatus(OSStatus)
    case invalidStoredValue
}

struct KeychainStore: Sendable {
    private let service: String
    private let account: String

    init(service: String = "com.ffpng.app", account: String = "tinify-api-key") {
        self.service = service
        self.account = account
    }

    func save(_ apiKey: String) throws {
        let data = Data(apiKey.utf8)
        let query = itemQuery
        let update = [kSecValueData as String: data] as CFDictionary
        let updateStatus = SecItemUpdate(query as CFDictionary, update)

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainStoreFailure.unexpectedStatus(addStatus)
            }
        default:
            throw KeychainStoreFailure.unexpectedStatus(updateStatus)
        }
    }

    func load() throws -> String? {
        var query = itemQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
                throw KeychainStoreFailure.invalidStoredValue
            }
            return key
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainStoreFailure.unexpectedStatus(status)
        }
    }

    func delete() throws {
        let status = SecItemDelete(itemQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreFailure.unexpectedStatus(status)
        }
    }

    private var itemQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
