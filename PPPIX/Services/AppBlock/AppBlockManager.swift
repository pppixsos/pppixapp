import Foundation
import UIKit

// Representa um app instalado no iPhone
struct InstalledApp: Identifiable, Codable {
    let id: String       // bundle ID
    let name: String
    let iconData: Data?  // ícone PNG
    var isBlocked: Bool
    var profileInstalled: Bool
}

#if !targetEnvironment(simulator)
import ManagedSettings
import FamilyControls

@MainActor
final class AppBlockManager: ObservableObject {

    static let shared = AppBlockManager()
    private init() { loadBlockedApps() }

    private let store = ManagedSettingsStore()
    private let sharedDefaults = UserDefaults(suiteName: "group.tech.pppix.app")
    private let server = LocalWebServer.shared

    @Published var installedApps: [InstalledApp] = []
    @Published var blockedApps: [InstalledApp] = []
    @Published var isLoadingApps = false

    func loadInstalledApps() {
        guard installedApps.isEmpty else { return }
        isLoadingApps = true
        Task.detached(priority: .userInitiated) {
            let apps = await Self.fetchInstalledApps()
            await MainActor.run {
                self.installedApps = apps
                self.isLoadingApps = false
            }
        }
    }

    private static func fetchInstalledApps() async -> [InstalledApp] {
        var result: [InstalledApp] = []
        guard
            let workspaceClass = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type,
            let workspace = workspaceClass.perform(Selector(("defaultWorkspace")))?.takeUnretainedValue() as? NSObject,
            let appsRaw = workspace.perform(Selector(("allInstalledApplications")))?.takeUnretainedValue() as? [NSObject]
        else { return [] }

        let excluded = Set(["tech.pppix.app"])
        let systemPrefixes = ["com.apple."]

        for app in appsRaw {
            guard
                let bundleId = app.perform(Selector(("applicationIdentifier")))?.takeUnretainedValue() as? String,
                !excluded.contains(bundleId),
                !systemPrefixes.contains(where: { bundleId.hasPrefix($0) }),
                let appName = app.perform(Selector(("localizedName")))?.takeUnretainedValue() as? String,
                !appName.isEmpty
            else { continue }

            var iconData: Data? = nil
            if let bundleURL = app.perform(Selector(("bundleURL")))?.takeUnretainedValue() as? URL,
               let bundle = Bundle(url: bundleURL) {
                iconData = iconDataFromBundle(bundle)
            }
            result.append(InstalledApp(id: bundleId, name: appName, iconData: iconData, isBlocked: false, profileInstalled: false))
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func iconDataFromBundle(_ bundle: Bundle) -> Data? {
        if let icons = bundle.infoDictionary?["CFBundleIcons"] as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primary["CFBundleIconFiles"] as? [String],
           let lastName = files.last {
            for suffix in ["@3x", "@2x", ""] {
                if let img = UIImage(named: lastName + suffix, in: bundle, compatibleWith: nil),
                   let data = img.pngData() { return data }
            }
        }
        if let iconFile = bundle.infoDictionary?["CFBundleIconFile"] as? String,
           let img = UIImage(named: iconFile, in: bundle, compatibleWith: nil) {
            return img.pngData()
        }
        return nil
    }

    func blockApp(_ app: InstalledApp, completion: @escaping (Bool) -> Void) {
        server.startIfNeeded()
        let profileURL = server.serveProfile(for: app)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            UIApplication.shared.open(profileURL) { [weak self] success in
                self?.saveBlockedApp(app)
                completion(success)
            }
        }
    }

    func unblockApp(_ app: InstalledApp) {
        restoreBlockedApplications(excluding: app.id)
        removeBlockedApp(id: app.id)
    }

    func openRealApp(bundleId: String) {
        restoreBlockedApplications(excluding: bundleId)
        openAppByBundleId(bundleId)
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            self?.restoreBlockedApplications(excluding: nil)
        }
    }

    private func openAppByBundleId(_ bundleId: String) {
        guard
            let workspaceClass = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type,
            let workspace = workspaceClass.perform(Selector(("defaultWorkspace")))?.takeUnretainedValue() as? NSObject
        else { return }
        let sel = Selector(("openApplicationWithBundleID:"))
        if workspace.responds(to: sel) {
            workspace.perform(sel, with: bundleId)
        }
    }

    func saveToken(_ token: ApplicationToken, forBundleId bundleId: String) {
        if let data = try? JSONEncoder().encode(token) {
            sharedDefaults?.set(data, forKey: "pppix_token_\(bundleId)")
        }
    }

    private func restoreBlockedApplications(excluding bundleId: String?) {
        var allTokens: Set<ApplicationToken> = []
        for app in blockedApps where app.id != bundleId {
            if let data = sharedDefaults?.data(forKey: "pppix_token_\(app.id)"),
               let token = try? JSONDecoder().decode(ApplicationToken.self, from: data) {
                allTokens.insert(token)
            }
        }
        store.application.blockedApplications = allTokens.isEmpty ? nil : allTokens
    }

    private func saveBlockedApp(_ app: InstalledApp) {
        var current = blockedApps
        current.removeAll { $0.id == app.id }
        var updated = app
        updated.isBlocked = true
        updated.profileInstalled = true
        current.append(updated)
        blockedApps = current
        persist()
    }

    private func removeBlockedApp(id: String) {
        blockedApps.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(blockedApps) {
            sharedDefaults?.set(data, forKey: "pppix_blocked_apps")
        }
    }

    private func loadBlockedApps() {
        guard let data = sharedDefaults?.data(forKey: "pppix_blocked_apps"),
              let apps = try? JSONDecoder().decode([InstalledApp].self, from: data)
        else { return }
        blockedApps = apps
    }
}

#else

// Stub para simulador
@MainActor
final class AppBlockManager: ObservableObject {
    static let shared = AppBlockManager()
    private init() {}
    @Published var installedApps: [InstalledApp] = []
    @Published var blockedApps: [InstalledApp] = []
    @Published var isLoadingApps = false
    func loadInstalledApps() {}
    func blockApp(_ app: InstalledApp, completion: @escaping (Bool) -> Void) { completion(false) }
    func unblockApp(_ app: InstalledApp) {}
    func openRealApp(bundleId: String) {}
}

#endif
