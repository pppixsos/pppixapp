import Foundation
import Security

/// Equivalente ao SessionManager.kt do Android.
/// Tokens são salvos no Keychain (seguro). Demais dados no UserDefaults.
@MainActor
final class SessionManager: ObservableObject {

    static let shared = SessionManager()
    private init() { loadFromStorage() }

    // MARK: - Published (reactive)

    @Published private(set) var isLoggedIn: Bool = false
    @Published private(set) var userId: Int = 0
    @Published private(set) var userName: String = ""
    @Published private(set) var userEmail: String = ""

    // MARK: - Keys

    private enum Key {
        static let userId       = "pppix_user_id"
        static let userName     = "pppix_user_name"
        static let userEmail    = "pppix_user_email"
        static let fcmToken     = "pppix_fcm_token"
        static let fcmDeviceId  = "pppix_fcm_device_id"
        static let blockedApps  = "pppix_blocked_apps"
        static let monitorActive = "pppix_monitor_active"
        static let permAsked    = "pppix_permissions_asked"
        static let pwdConfigured = "pppix_passwords_configured"

        // Keychain
        static let accessToken  = "pppix_access_token"
        static let refreshToken = "pppix_refresh_token"
    }

    private let defaults = UserDefaults(suiteName: "group.tech.pppix.app") ?? UserDefaults.standard

    // MARK: - Load on init

    private func loadFromStorage() {
        userId    = defaults.integer(forKey: Key.userId)
        userName  = defaults.string(forKey: Key.userName) ?? ""
        userEmail = defaults.string(forKey: Key.userEmail) ?? ""
        isLoggedIn = accessToken != nil
    }

    // MARK: - Tokens (Keychain)

    var accessToken: String? {
        get { keychainGet(key: Key.accessToken) }
        set {
            if let v = newValue { keychainSet(key: Key.accessToken, value: v) }
            else { keychainDelete(key: Key.accessToken) }
        }
    }

    var refreshToken: String? {
        get { keychainGet(key: Key.refreshToken) }
        set {
            if let v = newValue { keychainSet(key: Key.refreshToken, value: v) }
            else { keychainDelete(key: Key.refreshToken) }
        }
    }

    func saveTokens(access: String, refresh: String) {
        accessToken = access
        refreshToken = refresh
        DispatchQueue.main.async { self.isLoggedIn = true }
    }

    // MARK: - User Info

    func saveUserInfo(id: Int, email: String, name: String) {
        userId    = id
        userEmail = email
        userName  = name
        defaults.set(id,    forKey: Key.userId)
        defaults.set(email, forKey: Key.userEmail)
        defaults.set(name,  forKey: Key.userName)
    }

    // MARK: - FCM

    var fcmToken: String? {
        get { defaults.string(forKey: Key.fcmToken) }
        set { defaults.set(newValue, forKey: Key.fcmToken) }
    }

    var fcmDeviceId: Int {
        get { defaults.integer(forKey: Key.fcmDeviceId) }
        set { defaults.set(newValue, forKey: Key.fcmDeviceId) }
    }

    // MARK: - Blocked Apps (Screen Time bundles)

    var blockedApps: Set<String> {
        get {
            let arr = defaults.stringArray(forKey: Key.blockedApps) ?? []
            return Set(arr)
        }
        set { defaults.set(Array(newValue), forKey: Key.blockedApps) }
    }

    func isAppBlocked(_ bundleId: String) -> Bool {
        blockedApps.contains(bundleId)
    }

    // MARK: - Monitor / Permissions

    // MARK: - FamilyActivity Selection (salva como Data para rebloquear após unlock)
    func saveLastSelectionData(_ data: Data) {
        defaults.set(data, forKey: "pppix_last_selection")
    }

    func loadLastSelectionData() -> Data? {
        return defaults.data(forKey: "pppix_last_selection")
    }

    var isMonitorActive: Bool {
        get { defaults.bool(forKey: Key.monitorActive) }
        set { defaults.set(newValue, forKey: Key.monitorActive) }
    }

    var werePermissionsAsked: Bool {
        get { defaults.bool(forKey: Key.permAsked) }
        set { defaults.set(newValue, forKey: Key.permAsked) }
    }

    var arePasswordsConfigured: Bool {
        get { defaults.bool(forKey: Key.pwdConfigured) }
        set { defaults.set(newValue, forKey: Key.pwdConfigured) }
    }

    // MARK: - Logout

    func clearSession() {
        let blocked  = blockedApps
        let permAsked = werePermissionsAsked

        // Limpa UserDefaults
        let domain = Bundle.main.bundleIdentifier!
        defaults.removePersistentDomain(forName: domain)

        // Limpa Keychain
        keychainDelete(key: Key.accessToken)
        keychainDelete(key: Key.refreshToken)

        // Preserva configurações de bloqueio
        blockedApps = blocked
        werePermissionsAsked = permAsked

        // Recarrega estado
        userId    = 0
        userName  = ""
        userEmail = ""
        DispatchQueue.main.async { self.isLoggedIn = false }
    }

    // MARK: - Keychain helpers

    // AccessGroup compartilhado entre app principal e todas as extensions
    private let keychainGroup = "K5SWZ92Z64.group.tech.pppix.app"

    private func keychainSet(key: String, value: String) {
        let data = value.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      "tech.pppix.app",
            kSecAttrAccount as String:      key,
            kSecValueData as String:        data,
            kSecAttrAccessible as String:   kSecAttrAccessibleAfterFirstUnlock,
            kSecAttrAccessGroup as String:  keychainGroup
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func keychainGet(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      "tech.pppix.app",
            kSecAttrAccount as String:      key,
            kSecReturnData as String:       true,
            kSecMatchLimit as String:       kSecMatchLimitOne,
            kSecAttrAccessGroup as String:  keychainGroup
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status != errSecSuccess {
            // Fallback: tentar sem AccessGroup (tokens salvos antes desta versão)
            let fallbackQuery: [String: Any] = [
                kSecClass as String:       kSecClassGenericPassword,
                kSecAttrAccount as String: key,
                kSecReturnData as String:  true,
                kSecMatchLimit as String:  kSecMatchLimitOne
            ]
            var fallbackResult: AnyObject?
            SecItemCopyMatching(fallbackQuery as CFDictionary, &fallbackResult)
            if let data = fallbackResult as? Data, let value = String(data: data, encoding: .utf8) {
                // Migrar para o novo formato com AccessGroup
                keychainSet(key: key, value: value)
                return value
            }
            return nil
        }
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func keychainDelete(key: String) {
        let query: [String: Any] = [
            kSecClass as String:           kSecClassGenericPassword,
            kSecAttrService as String:     "tech.pppix.app",
            kSecAttrAccount as String:     key,
            kSecAttrAccessGroup as String: keychainGroup
        ]
        SecItemDelete(query as CFDictionary)
        // Também deletar versão sem AccessGroup
        let legacyQuery: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(legacyQuery as CFDictionary)
    }
}
