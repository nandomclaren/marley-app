import Foundation
import Security

/// Secrets (GitHub token, Anthropic key) live in the iOS Keychain, never in files or the Gist.
enum Keychain {
    static let service = "com.marley.app"

    static func get(_ key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: key, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        let s = String(decoding: d, as: UTF8.self)
        return s.isEmpty ? nil : s
    }
    static func set(_ key: String, _ value: String?) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
        SecItemDelete(base as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
    static let githubToken = "github-token"
    static let gistId = "gist-id"
    static let anthropicKey = "anthropic-key"
}

/// Reads the key at call time, so changing it in Settings takes effect immediately.
struct KeychainAnthropicStreamer: AIStreamer {
    func stream(body: Data, onEvent: @escaping @Sendable (AIStreamEvent) -> Void) async throws -> AIResponse {
        guard let key = Keychain.get(Keychain.anthropicKey) else { throw AIError.noKey }
        return try await AnthropicStreamer(apiKey: key).stream(body: body, onEvent: onEvent)
    }
}
