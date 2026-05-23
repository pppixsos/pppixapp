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
        store.application.blockedApplications = selection.applicationTokens
        SessionManager.shared.isMonitorActive = true
    }

    func unblockAll() {
        store.clearAllSettings()
        SessionManager.shared.isMonitorActive = false
    }
}

#else

// Stub para simulador
@MainActor
final class ScreenTimeManager: ObservableObject {
    static let shared = ScreenTimeManager()
    private init() {}
    @Published var isAuthorized: Bool = false
    func requestAuthorization() async {}
    func unblockAll() {}
}

#endif
