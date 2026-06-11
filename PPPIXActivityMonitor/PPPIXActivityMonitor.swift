import DeviceActivity
import ManagedSettings
import Foundation

// Processo separado do sistema — roda mesmo com app principal fechado
// Com os entitlements corretos (family-controls + app-groups), aplica shield diretamente
class PPPIXActivityMonitor: DeviceActivityMonitor {

    private let store = ManagedSettingsStore(named: .init("pppix"))
    private let sharedDefaults = UserDefaults(suiteName: "group.tech.pppix.app")

    // Chamado quando o intervalo termina — este é o momento do relock
    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)

        let name = activity.rawValue
        guard name.hasPrefix("pppix.relock") || name.hasPrefix("pppix.reblock") else { return }

        // Só reblocar se o desbloqueio expirou
        let until = sharedDefaults?.double(forKey: "pppix_unlocked_until") ?? 0
        if Date().timeIntervalSince1970 < until - 1 { return }

        reapplyShield()
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name,
                                         activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        reapplyShield()
    }

    private func reapplyShield() {
        sharedDefaults?.removeObject(forKey: "pppix_unlocked_until")
        sharedDefaults?.removeObject(forKey: "pppix_relock_scheduled_at")
        sharedDefaults?.synchronize()

        // SEMPRE restaurar a partir da selecao COMPLETA salva (todos os
        // apps protegidos), nao do snapshot "before_unlock" de um unico
        // app. O snapshot parcial causava o bug de "desbloqueei 2 apps,
        // so' 1 volta a ser bloqueado": ele continha apenas o estado de
        // QUAL app estava sendo desbloqueado naquele momento, e se outro
        // app ja tinha sido desbloqueado antes, ficava de fora pra sempre.
        if let data = sharedDefaults?.data(forKey: "pppix_activity_selection"),
           let sel = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data),
           !sel.applicationTokens.isEmpty || !sel.categoryTokens.isEmpty {
            store.shield.applications = sel.applicationTokens.isEmpty ? nil : sel.applicationTokens
            store.shield.applicationCategories = sel.categoryTokens.isEmpty ? nil : .specific(sel.categoryTokens)
            store.shield.webDomains = sel.webDomainTokens.isEmpty ? nil : sel.webDomainTokens
            sharedDefaults?.removeObject(forKey: "pppix_shield_apps_before_unlock")
            sharedDefaults?.removeObject(forKey: "pppix_single_app_token_data")
            sharedDefaults?.synchronize()
            return
        }

        // Fallback (selecao completa nao disponivel): usar snapshot parcial
        if let beforeData = sharedDefaults?.data(forKey: "pppix_shield_apps_before_unlock"),
           let apps = try? JSONDecoder().decode(Set<ApplicationToken>.self, from: beforeData),
           !apps.isEmpty {
            store.shield.applications = apps
        }
    }
}
