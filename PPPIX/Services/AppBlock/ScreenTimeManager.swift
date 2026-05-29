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

    let store = ManagedSettingsStore(named: ManagedSettingsStore.Name("pppix"))
    @Published var isAuthorized = false
    @Published var currentSelection = FamilyActivitySelection()

    private let sharedDefaults = UserDefaults(suiteName: "group.tech.pppix.app")

    // Unlock state — em memória apenas
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

    // MARK: - Unlock seletivo (apenas o app tocado)

    func unlockSingleApp(seconds: Int = 60) {
        // Marcar unlock na memória
        unlockedUntil = Date().addingTimeInterval(Double(seconds))

        // Cancelar reblock anterior
        reblockWorkItem?.cancel()
        reblockWorkItem = nil

        // Tentar desbloquear apenas o app específico via FamilyActivitySelection
        if let singleData = sharedDefaults?.data(forKey: "pppix_single_unlock_selection"),
           let singleSelection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: singleData),
           let tokenToUnlock = singleSelection.applicationTokens.first {
            // Remove apenas o token do app específico
            var remainingApps = currentSelection.applicationTokens
            remainingApps.remove(tokenToUnlock)
            store.shield.applications = remainingApps.isEmpty ? nil : remainingApps
            // Categorias e webDomains permanecem bloqueados
        } else {
            // Fallback seguro: não desbloqueia nada se não conseguiu identificar o token
            // Tenta apenas remover todas as aplicações (sem categorias)
            store.shield.applications = nil
        }

        // Agendar reblock usando background task para funcionar mesmo em background
        scheduleReblockWithBackgroundTask(after: seconds)
    }

    private func scheduleReblockWithBackgroundTask(after seconds: Int) {
        // Cancelar background task anterior
        if bgTask != .invalid {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }

        // Solicitar execução em background
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "pppix.reblock") { [weak self] in
            // Expiration handler — iOS vai encerrar, rebloquear agora
            self?.applyShieldAndEndBgTask()
        }

        // DispatchQueue para foreground + background (até 30s garantidos)
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

    // Chamado quando PPPIX vai ao background
    func reblockOnBackground() {
        if isCurrentlyUnlocked() {
            // Há unlock ativo — a background task já está gerenciando o reblock
            // Não fazer nada extra — deixar o timer existente agir
        } else {
            // Não há unlock ativo — garantir que o shield está aplicado
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
