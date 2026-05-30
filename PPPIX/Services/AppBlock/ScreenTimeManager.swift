import Foundation
import SwiftUI
import UIKit

#if !targetEnvironment(simulator)
import FamilyControls
import ManagedSettings

@MainActor
final class ScreenTimeManager: ObservableObject {

    static let shared = ScreenTimeManager()
    private init() {}

    let store = ManagedSettingsStore(named: ManagedSettingsStore.Name("pppix"))
    @Published var isAuthorized = false
    @Published var currentSelection = FamilyActivitySelection()

    private let sharedDefaults = UserDefaults(suiteName: "group.tech.pppix.app")
    static let selectionKey = "pppix_activity_selection"

    private var reblockWorkItem: DispatchWorkItem?
    private var bgTask: UIBackgroundTaskIdentifier = .invalid

    // MARK: - Autorização

    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            isAuthorized = true
            loadSavedSelection()
            applyShield()
        } catch { isAuthorized = false }
    }

    func checkAuthorization() {
        isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
        if isAuthorized {
            loadSavedSelection()
            if !isCurrentlyUnlocked() { applyShield() }
        }
    }

    func syncCheckAndReblock() {
        guard isAuthorized, hasBlockedApps else { return }
        if !isCurrentlyUnlocked() { applyShield() }
    }

    func isCurrentlyUnlocked() -> Bool {
        let until = sharedDefaults?.double(forKey: "pppix_unlocked_until") ?? 0
        return until > Date().timeIntervalSince1970
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
        sharedDefaults?.removeObject(forKey: "pppix_unlocked_until")
        sharedDefaults?.synchronize()
        cancelReblock()
    }

    // MARK: - Unlock individual (chamado APÓS senha correta)

    func unlockSingleApp(reblockAfterSeconds: Int = 20) {
        sharedDefaults?.removeObject(forKey: "pppix_password_request_time")

        // Remove shield do app específico (ou todos como fallback)
        if let tokenData = sharedDefaults?.data(forKey: "pppix_single_app_token_data"),
           let singleToken = try? JSONDecoder().decode(ApplicationToken.self, from: tokenData) {
            var remaining = store.shield.applications ?? currentSelection.applicationTokens
            remaining.remove(singleToken)
            store.shield.applications = remaining.isEmpty ? nil : remaining
        } else {
            store.shield.applications = nil
        }

        // Grava timestamp de expiração do desbloqueio
        let until = Date().timeIntervalSince1970 + Double(reblockAfterSeconds)
        sharedDefaults?.set(until, forKey: "pppix_unlocked_until")
        sharedDefaults?.synchronize()

        // Agenda reblock SOMENTE para quando o app for para background
        // O shield só é reapplicado quando o usuário sair do PPPIX
        scheduleReblock(afterSeconds: reblockAfterSeconds)
    }

    // MARK: - Reblock
    // O reblock acontece em DUAS situações:
    // 1. O app PPPIX vai para background (scenePhase → .background no RootView)
    // 2. O timer de 20s expira E o app PPPIX já está em background

    private func scheduleReblock(afterSeconds seconds: Int) {
        cancelReblock()
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "pppix.reblock") { [weak self] in
            self?.applyShieldIfExpired()
        }
        let workItem = DispatchWorkItem { [weak self] in
            self?.applyShieldIfExpired()
        }
        reblockWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(seconds), execute: workItem)
    }

    private func cancelReblock() {
        reblockWorkItem?.cancel()
        reblockWorkItem = nil
        if bgTask != .invalid {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
    }

    // Chamado quando o timer expira — só bloqueia se o desbloqueio já expirou
    private func applyShieldIfExpired() {
        guard !isCurrentlyUnlocked() else {
            // Ainda dentro do tempo — cancelar
            cancelReblock()
            return
        }
        // Expirou — verificar se app PPPIX está em foreground
        let state = UIApplication.shared.applicationState
        if state == .active {
            // PPPIX ainda em foreground — NÃO bloquear, retentar em 3s
            let workItem = DispatchWorkItem { [weak self] in self?.applyShieldIfExpired() }
            reblockWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: workItem)
        } else {
            // App em background — aplicar shield e limpar
            sharedDefaults?.removeObject(forKey: "pppix_unlocked_until")
            sharedDefaults?.synchronize()
            applyShield()
            cancelReblock()
        }
    }

    // Chamado quando scenePhase → .background no RootView
    func reblockOnBackground() {
        // Ao ir para background, aplica shield se tempo expirou
        if !isCurrentlyUnlocked() {
            sharedDefaults?.removeObject(forKey: "pppix_unlocked_until")
            sharedDefaults?.synchronize()
            applyShield()
            cancelReblock()
        }
        // Se ainda dentro do tempo, o timer já está agendado e cuidará disso
    }

    // Compatibilidade
    func unlockTemporarily(seconds: Int = 20) { unlockSingleApp(reblockAfterSeconds: seconds) }
    func unblockAll() { unlockSingleApp(reblockAfterSeconds: 20) }
    func reblockAfterUnlock() { syncCheckAndReblock() }
    func reblockAfterPasswordVerified() {}

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
    func applyShield() {}
    func removeShield() {}
    func unlockSingleApp(reblockAfterSeconds: Int = 20) {}
    func unlockTemporarily(seconds: Int = 20) {}
    func unblockAll() {}
    func reblockAfterUnlock() {}
    func reblockOnBackground() {}
    func syncCheckAndReblock() {}
    func loadSavedSelection() {}
    func isCurrentlyUnlocked() -> Bool { false }
    func reblockAfterPasswordVerified() {}
    var hasBlockedApps: Bool { false }
}

#endif
