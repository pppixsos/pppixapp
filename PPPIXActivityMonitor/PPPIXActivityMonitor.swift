import DeviceActivity
import ManagedSettings
import Foundation

class PPPIXActivityMonitor: DeviceActivityMonitor {

    private let store = ManagedSettingsStore(named: .init("pppix"))
    private let sharedDefaults = UserDefaults(suiteName: "group.tech.pppix.app")

    // Chamado quando o intervalo de unlock termina — REBLOQUEIA
    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)

        guard activity.rawValue == "pppix.reblock" else { return }

        // Verifica se o unlock realmente expirou (nunca confiar só no evento)
        let unlockUntil = sharedDefaults?.double(forKey: "pppix_unlocked_until") ?? 0
        guard Date().timeIntervalSince1970 >= unlockUntil - 1 else { return }

        // Limpa flag
        sharedDefaults?.removeObject(forKey: "pppix_unlocked_until")
        sharedDefaults?.synchronize()

        // Reaplica o shield — síncrono, sem async
        reapplyShield()
    }

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        // Não faz nada no início — só no fim
    }

    private func reapplyShield() {
        guard let data = sharedDefaults?.data(forKey: "pppix_activity_selection"),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data),
              !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty
        else { return }

        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
    }
}
