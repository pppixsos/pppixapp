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
        // Salva a seleção para poder rebloquear após unlock temporário
        SessionManager.shared.saveLastSelection(selection)
    }

    func unblockAll() {
        store.clearAllSettings()
        SessionManager.shared.isMonitorActive = false
    }

    func reblockIfNeeded() {
        guard SessionManager.shared.isMonitorActive else { return }
        if let selection = SessionManager.shared.loadLastSelection() {
            blockApps(selection)
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
    func reblockIfNeeded() {}
}
#endif
