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

    // Store padrão (sem nome) — mais compatível com iOS 26
    let store = ManagedSettingsStore()
    @Published var isAuthorized = false
    @Published var currentSelection = FamilyActivitySelection()

    private let sharedDefaults = UserDefaults(suiteName: "group.tech.pppix.app")
    static let selectionKey = "pppix_activity_selection"

    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            isAuthorized = true
            loadSavedSelection()
        } catch {
            isAuthorized = false
        }
    }

    func checkAuthorization() {
        isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
        if isAuthorized { loadSavedSelection() }
    }

    // Chamado quando usuário confirma seleção no FamilyActivityPicker
    func applySelection(_ selection: FamilyActivitySelection) {
        currentSelection = selection
        saveSelection(selection)
        blockSelected(selection)
    }

    func blockSelected(_ selection: FamilyActivitySelection) {
        let apps = selection.applicationTokens
        let cats = selection.categoryTokens
        store.shield.applications = apps.isEmpty ? nil : apps
        store.shield.applicationCategories = cats.isEmpty ? nil : .specific(cats)
    }

    func unblockAll() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
    }

    // Rebloqueia após senha digitada (chamado pelo ShieldAction via UserDefaults)
    func reblockAfterUnlock() {
        guard isAuthorized else { return }
        loadSavedSelection()
        blockSelected(currentSelection)
    }

    private func saveSelection(_ selection: FamilyActivitySelection) {
        if let data = try? JSONEncoder().encode(selection) {
            sharedDefaults?.set(data, forKey: Self.selectionKey)
            sharedDefaults?.synchronize()
        }
    }

    func loadSavedSelection() {
        guard let data = sharedDefaults?.data(forKey: Self.selectionKey),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        else { return }
        currentSelection = selection
    }

    var hasBlockedApps: Bool {
        !currentSelection.applicationTokens.isEmpty || !currentSelection.categoryTokens.isEmpty
    }
}

#else

@MainActor
final class ScreenTimeManager: ObservableObject {
    static let shared = ScreenTimeManager()
    private init() {}
    @Published var isAuthorized = false
    func requestAuthorization() async {}
    func checkAuthorization() {}
    func applySelection(_ selection: Any) {}
    func blockSelected(_ selection: Any) {}
    func unblockAll() {}
    func reblockAfterUnlock() {}
    func loadSavedSelection() {}
    var hasBlockedApps: Bool { false }
}

#endif
