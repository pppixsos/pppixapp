import DeviceActivity
import ManagedSettings
import Foundation

class PPPIXActivityMonitor: DeviceActivityMonitor {

    // Store com mesmo nome do app principal — obrigatório
    private let store = ManagedSettingsStore(named: .init("pppix"))
    private let sharedDefaults = UserDefaults(suiteName: "group.tech.pppix.app")

    // Chamado quando o intervalo de desbloqueio termina — hora de rebloquear
    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)

        // Lição 6 do Habit Doom: sempre verificar timestamp, nunca confiar só em flag
        let unlockedUntil = sharedDefaults?.double(forKey: "pppix_unlocked_until") ?? 0
        let sessionExpired = unlockedUntil <= Date().timeIntervalSince1970

        if sessionExpired {
            reapplyShield()
        }
    }

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
    }

    // Lição 9 do Habit Doom: re-blocking SÍNCRONO, sem async
    private func reapplyShield() {
        guard let data = sharedDefaults?.data(forKey: "pppix_activity_selection") else { return }

        // Decodificar seleção salva
        if let selection = try? JSONDecoder().decode(
            SelectedAppsData.self, from: data
        ) {
            store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
            store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
            store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        }
    }
}

// Struct auxiliar para decodificar a seleção salva
private struct SelectedAppsData: Codable {
    var applicationTokens: Set<ApplicationToken> = []
    var categoryTokens: Set<ActivityCategoryToken> = []
    var webDomainTokens: Set<WebDomainToken> = []
}
