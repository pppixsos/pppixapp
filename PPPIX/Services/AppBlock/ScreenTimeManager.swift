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
    private var reblockWorkItem: DispatchWorkItem?

    static let selectionKey     = "pppix_activity_selection"
    static let unlockedUntilKey = "pppix_unlocked_until"

    // MARK: - Autorização

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
        if isAuthorized {
            loadSavedSelection()
            syncCheckAndReblock()
        }
    }

    // Verifica e reaplica shield se necessário — chamar sempre que app vier ao foreground
    func syncCheckAndReblock() {
        guard isAuthorized, hasBlockedApps else { return }
        let isUnlocked = isCurrentlyUnlocked()
        if !isUnlocked {
            applyShield()
        }
    }

    func isCurrentlyUnlocked() -> Bool {
        let unlockedUntil = sharedDefaults?.double(forKey: Self.unlockedUntilKey) ?? 0
        return unlockedUntil > Date().timeIntervalSince1970
    }

    // MARK: - Shield

    func applySelection(_ selection: FamilyActivitySelection) {
        currentSelection = selection
        saveSelection(selection)
        applyShield()
    }

    func applyShield() {
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

    // MARK: - Unlock seletivo (apenas o app específico, mantém os outros bloqueados)

    func unlockSingleApp(seconds: Int = 60) {
        // 1. Marcar como desbloqueado
        let until = Date().timeIntervalSince1970 + Double(seconds)
        sharedDefaults?.set(until, forKey: Self.unlockedUntilKey)
        sharedDefaults?.synchronize()

        // 2. Cancelar timer anterior
        reblockWorkItem?.cancel()
        reblockWorkItem = nil

        // 3. Remover APENAS o token do app específico — manter os outros bloqueados
        if let tokenData = sharedDefaults?.data(forKey: "pppix_target_app_token"),
           let token = try? JSONDecoder().decode(ApplicationToken.self, from: tokenData) {
            // Remove só o app que o usuário está tentando abrir
            var remainingApps = currentSelection.applicationTokens
            remainingApps.remove(token)
            store.shield.applications = remainingApps.isEmpty ? nil : remainingApps
            // Categorias e webdomains permanecem bloqueados
        } else {
            // Fallback: remove tudo (comportamento anterior)
            store.shield.applications = nil
            store.shield.applicationCategories = nil
            store.shield.webDomains = nil
        }

        // 4. Reagendar reblock após X segundos
        scheduleReblock(after: seconds)
    }

    // Reblock via BGAppRefreshTask + DispatchQueue (dupla proteção)
    private func scheduleReblock(after seconds: Int) {
        // DispatchQueue (funciona quando app está em foreground)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.sharedDefaults?.removeObject(forKey: Self.unlockedUntilKey)
            self.sharedDefaults?.synchronize()
            self.applyShield()
        }
        reblockWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(seconds), execute: workItem)
    }

    // Chamado quando PPPIX vai ao background — rebloqueia se não há unlock ativo
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
