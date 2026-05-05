import Foundation
import Security

/// 시크릿(API key, bot token 등) 영속화를 위한 추상화.
///
/// 프로덕션은 `LiveKeychainStore` (macOS Keychain),
/// 테스트는 `InMemoryKeychainStore`.
public protocol KeychainStore: Sendable {
    func set(_ value: String, for key: String) async throws
    func get(_ key: String) async throws -> String?
    func remove(_ key: String) async throws
}

/// 맥 Keychain을 사용하는 실제 구현.
///
/// `service`는 `com.yuminai`로 통일. 항목은 `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`로
/// 다른 디바이스 동기화를 차단한다.
public actor LiveKeychainStore: KeychainStore {
    public static let defaultService = "com.yuminai"

    private let service: String

    public init(service: String = LiveKeychainStore.defaultService) {
        self.service = service
    }

    public func set(_ value: String, for key: String) async throws {
        let data = Data(value.utf8)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        // upsert: 기존 항목 삭제 → 추가. 단순/안전.
        SecItemDelete(baseQuery as CFDictionary)

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw YuminaiError.keychainWriteFailed(status: status)
        }
    }

    public func get(_ key: String) async throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecItemNotFound:
            return nil
        case errSecSuccess:
            guard let data = result as? Data else {
                throw YuminaiError.keychainReadFailed(status: status)
            }
            return String(decoding: data, as: UTF8.self)
        default:
            throw YuminaiError.keychainReadFailed(status: status)
        }
    }

    public func remove(_ key: String) async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw YuminaiError.keychainWriteFailed(status: status)
        }
    }
}

/// 테스트용 인메모리 구현. Keychain을 건드리지 않는다.
public final actor InMemoryKeychainStore: KeychainStore {
    private var storage: [String: String] = [:]

    public init() {}

    public func set(_ value: String, for key: String) async throws {
        storage[key] = value
    }

    public func get(_ key: String) async throws -> String? {
        storage[key]
    }

    public func remove(_ key: String) async throws {
        storage.removeValue(forKey: key)
    }
}

/// Yuminai에서 사용하는 표준 Keychain account 이름.
public enum KeychainKey {
    public static let anthropicAPIKey = "anthropic_api_key"
    public static let telegramBotToken = "telegram_bot_token"
    public static let telegramChatID = "telegram_chat_id"
    public static let obsidianVaultPath = "obsidian_vault_path"
    /// **ADR-119** — GitHub Personal Access Token (코드 검색 API 인증용).
    public static let githubPersonalAccessToken = "yuminai.github.pat"
}
