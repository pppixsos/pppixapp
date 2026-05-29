import Foundation
import SwiftUI
import UIKit

#if !targetEnvironment(simulator)
import FamilyControls
import ManagedSettings
import DeviceActivity

@MainActor
final class ScreenTimeManager: ObservableObject {

    static let shared = ScreenTimeManager()
    private init() {}

    // Store principal — bloqueia todos os apps selecionados
    let store = ManagedSettingsStore(named: ManagedSettingsStore.Name("pppix"))
    @Published var isAuthorized = false
    @Published var currentSelection = FamilyActivitySelection()

    private let sharedDefaults = UserDefaults(suiteName: "group.tech.pppix.app")

    // Unlock state
    private var unlockedUntil: Date = .distantPast
    private var reblockWorkItem: DispatchWorkItem?
    private var bgTask: UIBackgroundTaskIdentifier = .invalid

    static let selectionKey = "pppix_activity_selection"

    // MARK: - Autorização

    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            isAuthorized = true
            loadSavedSelection()
            applyShield()
        } catch {
            isAuthorized = false
        }
    }

    func checkAuthorization() {
        isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
        if isAuthorized {
            loadSavedSelection()
            if !isCurrentlyUnlocked() {
                applyShield()
            }
        }
    }

    func syncCheckAndReblock() {
        guard isAuthorized, hasBlockedApps else { return }
        if !isCurrentlyUnlocked() {
            applyShield()
        }
    }

    func isCurrentlyUnlocked() -> Bool {
        return unlockedUntil > Date()
    }

    // MARK: - Shield

    func applySelection(_ selection: FamilyActivitySelection) {
        currentSelection = selection
        saveSelection(selection)
        applyShield()
    }

    func applyShield() {
        guard hasBlockedApps else { return }
        store.shield.applications = currentSelection.applicationTokens.isEmpty ? nil : currentSelection.applicationTokens
        store.shield.applicationCategories = currentSelection.categoryTokens.isEmpty ? nil : .specific(currentSelection.categoryTokens)
        store.shield.webDomains = currentSelection.webDomainTokens.isEmpty ? nil : currentSelection.webDomainTokens
    }

    func removeShield() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
    }

    // MARK: - Unlock seletivo (apenas o app tocado)
    //
    // ESTRATÉGIA:
    // O ShieldConfigurationExtension salva o ApplicationToken do app que foi
    // tocado em "pppix_single_app_token_data" como Data bruto (não FamilyActivitySelection).
    // Aqui, tentamos remover APENAS esse token do store principal.
    // Se não conseguir decodificar, remove todos (fallback seguro para o usuário).
    //
    func unlockSingleApp(seconds: Int = 60) {
        unlockedUntil = Date().addingTimeInterval(Double(seconds))
        reblockWorkItem?.cancel()
        reblockWorkItem = nil

        // Tentar desbloquear apenas o app específico
        if let tokenData = sharedDefaults?.data(forKey: "pppix_single_app_token_data"),
           let singleToken = try? JSONDecoder().decode(ApplicationToken.self, from: tokenData) {

            // Remove APENAS o token do app tocado do store principal
            var remaining = currentSelection.applicationTokens
            remaining.remove(singleToken)
            store.shield.applications = remaining.isEmpty ? nil : remaining
            // Categorias e webDomains permanecem bloqueados

        } else if let singleData = sharedDefaults?.data(forKey: "pppix_single_unlock_selection"),
                  let singleSelection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: singleData),
                  let tokenToUnlock = singleSelection.applicationTokens.first {

            // Fallback: usa FamilyActivitySelection salva
            var remaining = currentSelection.applicationTokens
            remaining.remove(tokenToUnlock)
            store.shield.applications = remaining.isEmpty ? nil : remaining

        } else {
            // Último fallback: remove todos os shields de aplicativos
            // (mantém categorias bloqueadas)
            store.shield.applications = nil
        }

        scheduleReblockWithBackgroundTask(after: seconds)
    }

    private func scheduleReblockWithBackgroundTask(after seconds: Int) {
        if bgTask != .invalid {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }

        bgTask = UIApplication.shared.beginBackgroundTask(withName: "pppix.reblock") { [weak self] in
            self?.applyShieldAndEndBgTask()
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.applyShieldAndEndBgTask()
        }
        reblockWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(seconds), execute: workItem)
    }

    private func applyShieldAndEndBgTask() {
        unlockedUntil = .distantPast
        applyShield()
        if bgTask != .invalid {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
    }

    func reblockOnBackground() {
        if !isCurrentlyUnlocked() {
            applyShield()
        }
    }

    // Compatibilidade
    func unlockTemporarily(seconds: Int = 60) { unlockSingleApp(seconds: seconds) }
    func unblockAll() { unlockSingleApp(seconds: 60) }
    func reblockAfterUnlock() { syncCheckAndReblock() }

    // MARK: - Persistência

    private func saveSelection(_ selection: FamilyActivitySelection) {
        if let data = try? JSONEncoder().encode(selection) {
            sharedDefaults?.set(data, forKey: Self.selectionKey)
            sharedDefaults?.synchronize()
        }
    }

    func loadSavedSelection() {
        guard let data = sharedDefaults?.data(forKey: Self.selectionKey),
              let sel = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        else { return }
        currentSelection = sel
    }

    var hasBlockedApps: Bool {
        !currentSelection.applicationTokens.isEmpty ||
        !currentSelection.categoryTokens.isEmpty
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
    func applyShield() {}
    func removeShield() {}
    func unlockSingleApp(seconds: Int = 60) {}
    func unlockTemporarily(seconds: Int = 60) {}
    func unblockAll() {}
    func reblockAfterUnlock() {}
    func reblockOnBackground() {}
    func syncCheckAndReblock() {}
    func loadSavedSelection() {}
    func isCurrentlyUnlocked() -> Bool { false }
    var hasBlockedApps: Bool { false }
}

#endif
