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
        // Migrar dados do UserDefaults.standard para o App Group (mudança do build 137)
        let standard = UserDefaults.standard
        if defaults !== standard {
            for key in [Key.userName, Key.userEmail] {
                if defaults.string(forKey: key) == nil,
                   let val = standard.string(forKey: key), !val.isEmpty {
                    defaults.set(val, forKey: key)
                }
            }
            if defaults.integer(forKey: Key.userId) == 0 {
                let id = standard.integer(forKey: Key.userId)
                if id > 0 { defaults.set(id, forKey: Key.userId) }
            }
            defaults.synchronize()
        }
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
        // Notificar app que usuário logou (para registrar FCM token)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .pppixUserDidLogin, object: nil)
        }
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

    // APNS token bruto (hex) para registro direto no backend
    var pendingApnsToken: String? {
        get { UserDefaults.standard.string(forKey: "pppix_pending_apns_token") }
        set { UserDefaults.standard.set(newValue, forKey: "pppix_pending_apns_token") }
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

        // Preservar IDs de alertas já vistos (não limpar no logout)
        let shownAlertIds = UserDefaults.standard.array(forKey: "pppix_shown_alert_ids")
        let processedAlertIds = UserDefaults.standard.array(forKey: "pppix_processed_alert_ids")

        // Limpa UserDefaults
        let domain = Bundle.main.bundleIdentifier!
        defaults.removePersistentDomain(forName: domain)

        // Restaurar IDs de alertas (persistem entre sessões)
        if let ids = shownAlertIds { UserDefaults.standard.set(ids, forKey: "pppix_shown_alert_ids") }
        if let ids = processedAlertIds { UserDefaults.standard.set(ids, forKey: "pppix_processed_alert_ids") }

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

    private func keychainSet(key: String, value: String) {
        let data = value.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String:           kSecClassGenericPassword,
            kSecAttrAccount as String:     key,
            kSecValueData as String:       data,
            kSecAttrAccessible as String:  kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func keychainGet(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func keychainDelete(key: String) {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

extension Notification.Name {
    static let pppixUserDidLogin = Notification.Name("pppix.userDidLogin")
}
