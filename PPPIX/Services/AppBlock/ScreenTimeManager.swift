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

    let store = ManagedSettingsStore(named: ManagedSettingsStore.Name("pppix"))
    @Published var isAuthorized = false
    @Published var currentSelection = FamilyActivitySelection()

    private let sharedDefaults = UserDefaults(suiteName: "group.tech.pppix.app")

    // Estado de unlock APENAS em memória — nunca persiste no disco
    // Quando app é morto e reaberto, shield sempre volta
    private var unlockedUntil: Date = .distantPast
    private var reblockWorkItem: DispatchWorkItem?

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
            // Sempre reaplica o shield ao verificar — garante que está ativo
            applyShield()
        }
    }

    // Chamado ao voltar ao foreground
    func syncCheckAndReblock() {
        guard isAuthorized, hasBlockedApps else { return }
        // Se o unlock expirou, reaplica shield
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
        let apps = currentSelection.applicationTokens
        let cats = currentSelection.categoryTokens
        let webs = currentSelection.webDomainTokens
        store.shield.applications = apps.isEmpty ? nil : apps
        store.shield.applicationCategories = cats.isEmpty ? nil : .specific(cats)
        store.shield.webDomains = webs.isEmpty ? nil : webs
    }

    func removeShield() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
    }

    // MARK: - Unlock apenas para o app específico

    func unlockSingleApp(seconds: Int = 60) {

        // Marcar como desbloqueado na memória
        unlockedUntil = Date().addingTimeInterval(Double(seconds))

        // Cancelar timer anterior
        reblockWorkItem?.cancel()
        reblockWorkItem = nil

        // Remover shield apenas do app específico
        if let tokenData = sharedDefaults?.data(forKey: "pppix_target_app_token"),
           let token = try? JSONDecoder().decode(ApplicationToken.self, from: tokenData) {
            var remaining = currentSelection.applicationTokens
            remaining.remove(token)
            store.shield.applications = remaining.isEmpty ? nil : remaining
            // Categorias e webDomains permanecem bloqueados
        } else {
            // Fallback
            store.shield.applications = nil
            store.shield.applicationCategories = nil
            store.shield.webDomains = nil
        }

        // Rebloquear após X segundos — funciona quando app está em foreground
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.unlockedUntil = .distantPast
            self.applyShield()
        }
        reblockWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(seconds), execute: workItem)
    }

    // Rebloqueia quando PPPIX vai ao background (se não há unlock ativo)
    func reblockOnBackground() {
        guard !isCurrentlyUnlocked() else { return }
        applyShield()
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
