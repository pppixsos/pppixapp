import Foundation
import SwiftUI

#if !targetEnvironment(simulator)
import FamilyControls
import ManagedSettings
import DeviceActivity

@MainActor
final class ScreenTimeManager: ObservableObject {

    static let shared = ScreenTimeManager()
    private init() {}

    // Store com nome explícito — deve coincidir com o ShieldConfigurationExtension
    let store = ManagedSettingsStore(named: ManagedSettingsStore.Name("pppix"))
    @Published var isAuthorized: Bool = false

    private let sharedDefaults = UserDefaults(suiteName: "group.tech.pppix.app")

    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            isAuthorized = true
        } catch {
            isAuthorized = false
        }
    }

    func blockApps(_ selection: FamilyActivitySelection) {
        store.shield.applications = selection.applicationTokens
        store.shield.applicationCategories = ShieldSettings.ActivityCategoryPolicy.specific(
            selection.categoryTokens
        )
        // Salvar seleção para rebloquear depois
        saveLastSelectionData(selection)
        SessionManager.shared.isMonitorActive = true
    }

    func unblockAll() {
        store.clearAllSettings()
        SessionManager.shared.isMonitorActive = false
    }

    func reblockFromSaved() {
        guard let data = sharedDefaults?.data(forKey: "pppix_last_selection"),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            return
        }
        store.shield.applications = selection.applicationTokens
        store.shield.applicationCategories = ShieldSettings.ActivityCategoryPolicy.specific(
            selection.categoryTokens
        )
        SessionManager.shared.isMonitorActive = true
    }

    func saveLastSelectionData(_ selection: FamilyActivitySelection) {
        if let data = try? JSONEncoder().encode(selection) {
            sharedDefaults?.set(data, forKey: "pppix_last_selection")
        }
    }
}

#else

@MainActor
final class ScreenTimeManager: ObservableObject {
    static let shared = ScreenTimeManager()
    private init() {}
    @Published var isAuthorized: Bool = false
    func requestAuthorization() async {}
    func unblockAll() {}
    func reblockFromSaved() {}
    func saveLastSelectionData(_ selection: Any) {}
    func blockApps(_ selection: Any) {}
}

#endif
