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

    private let store = ManagedSettingsStore()
    @Published var isAuthorized: Bool = false

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
        SessionManager.shared.isMonitorActive = true
        // Salva como Data para poder rebloquear depois
        if let data = try? JSONEncoder().encode(selection) {
            SessionManager.shared.saveLastSelectionData(data)
        }
    }

    func unblockAll() {
        store.clearAllSettings()
        SessionManager.shared.isMonitorActive = false
    }

    func reblockFromSaved() {
        guard let data = SessionManager.shared.loadLastSelectionData(),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else { return }
        blockApps(selection)
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
}
#endif
