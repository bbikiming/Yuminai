import Foundation

/// `AppPreferences`를 영속화하는 추상화. 시크릿 아니므로 UserDefaults / 파일이면 충분.
public protocol AppPreferencesStore: Sendable {
    func load() async throws -> AppPreferences
    func save(_ preferences: AppPreferences) async throws
}

/// `UserDefaults` 기반 구현.
public final actor UserDefaultsAppPreferencesStore: AppPreferencesStore {
    public static let defaultKey = "com.yuminai.AppPreferences"

    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = UserDefaultsAppPreferencesStore.defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    public func load() async throws -> AppPreferences {
        guard let data = defaults.data(forKey: key) else {
            return AppPreferences()
        }
        return try JSONDecoder().decode(AppPreferences.self, from: data)
    }

    public func save(_ preferences: AppPreferences) async throws {
        let data = try JSONEncoder().encode(preferences)
        defaults.set(data, forKey: key)
    }
}

/// 테스트용 인메모리 구현.
public final actor InMemoryAppPreferencesStore: AppPreferencesStore {
    private var current: AppPreferences

    public init(initial: AppPreferences = AppPreferences()) {
        self.current = initial
    }

    public func load() async throws -> AppPreferences { current }
    public func save(_ preferences: AppPreferences) async throws { current = preferences }
}
