import DeviceActivity
import ManagedSettings
import Foundation

// Camada extra de segurança — reaplica shield se o app principal não conseguiu
class PPPIXActivityMonitor: DeviceActivityMonitor {

    private let store = ManagedSettingsStore(named: .init("pppix"))
    private let sharedDefaults = UserDefaults(suiteName: "group.tech.pppix.app")

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        // Reaplica o shield quando qualquer intervalo termina
        let until = sharedDefaults?.double(forKey: "pppix_unlocked_until") ?? 0
        guard Date().timeIntervalSince1970 >= until - 1 else { return }
        reapplyShield()
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name,
                                         activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        reapplyShield()
    }

    private func reapplyShield() {
        sharedDefaults?.removeObject(forKey: "pppix_unlocked_until")
        sharedDefaults?.synchronize()

        guard let data = sharedDefaults?.data(forKey: "pppix_activity_selection"),
              let sel = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data),
              !sel.applicationTokens.isEmpty || !sel.categoryTokens.isEmpty
        else { return }

        store.shield.applications = sel.applicationTokens.isEmpty ? nil : sel.applicationTokens
        store.shield.applicationCategories = sel.categoryTokens.isEmpty ? nil : .specific(sel.categoryTokens)
        store.shield.webDomains = sel.webDomainTokens.isEmpty ? nil : sel.webDomainTokens
    }
}
