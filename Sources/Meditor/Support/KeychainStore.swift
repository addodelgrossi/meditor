import Foundation
import Security

protocol DeleteTokenStoring {
    func setDeleteToken(_ token: String, for id: String)
    func deleteToken(for id: String) -> String?
    func removeDeleteToken(for id: String)
}

/// Minimal Keychain wrapper for the secrets behind published links: each
/// share's delete token, keyed by its share id. Sandboxed apps get their own
/// keychain access group automatically, so no extra entitlement is required.
struct KeychainStore: DeleteTokenStoring {
    private static let service = "com.addodelgrossi.meditor.shareDeleteToken"

    func setDeleteToken(_ token: String, for id: String) {
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: id,
        ]
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func deleteToken(for id: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: id,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func removeDeleteToken(for id: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: id,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
