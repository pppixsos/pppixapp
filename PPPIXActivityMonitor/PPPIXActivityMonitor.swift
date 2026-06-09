import DeviceActivity
import ManagedSettings
import Foundation
import UserNotifications

// DeviceActivityMonitor — roda em processo separado, SEM precisar do app principal
// É a única forma confiável de reblock com app fechado no iOS
class PPPIXActivityMonitor: DeviceActivityMonitor {

    // CRÍTICO: usar ManagedSettingsStore com nome "pppix" — mesmo nome do app principal
    private let store = ManagedSettingsStore(named: .init("pppix"))
    private let sharedDefaults = UserDefaults(suiteName: "group.tech.pppix.app")

    // Chamado quando o intervalo de unlock termina — REBLOCK DEFINITIVO
    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)

        // Verifica se o desbloqueio já expirou
        let until = sharedDefaults?.double(forKey: "pppix_unlocked_until") ?? 0
        guard Date().timeIntervalSince1970 >= until - 1 else { return }

        reapplyShield()
    }

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        // Quando começa um intervalo de "reblock agendado", aplicar shield
        if activity.rawValue.hasPrefix("pppix.reblock") {
            reapplyShield()
        }
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name,
                                         activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        reapplyShield()
    }

    // REBLOCK DEFINITIVO — funciona sem o app principal estar aberto
    private func reapplyShield() {
        sharedDefaults?.removeObject(forKey: "pppix_unlocked_until")
        sharedDefaults?.synchronize()

        guard let data = sharedDefaults?.data(forKey: "pppix_activity_selection"),
              let sel = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data),
              (!sel.applicationTokens.isEmpty || !sel.categoryTokens.isEmpty)
        else {
            // Sem seleção salva — limpar tudo
            store.shield.applications = nil
            store.shield.applicationCategories = nil
            store.shield.webDomains = nil
            return
        }

        store.shield.applications = sel.applicationTokens.isEmpty ? nil : sel.applicationTokens
        store.shield.applicationCategories = sel.categoryTokens.isEmpty ? nil : .specific(sel.categoryTokens)
        store.shield.webDomains = sel.webDomainTokens.isEmpty ? nil : sel.webDomainTokens
    }
}
