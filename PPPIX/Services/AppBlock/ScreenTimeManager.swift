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

    // CAMADA 3: foreground check — chamado ao abrir o app
    func syncCheckAndReblock() {
        guard isAuthorized, hasBlockedApps else { return }
        if !isCurrentlyUnlocked() {
            applyShield()
        }
    }

    func isCurrentlyUnlocked() -> Bool {
        let unlockUntil = sharedDefaults?.double(forKey: "pppix_unlocked_until") ?? 0
        return unlockUntil > Date().timeIntervalSince1970
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
    }

    // MARK: - Unlock
    // NOTA: o unlock individual é feito diretamente pelo ShieldActionExtension
    // que já tem o ApplicationToken correto. O ScreenTimeManager só é chamado
    // após o usuário digitar a senha no PPPIX (após a notificação).
    func unlockSingleApp(seconds: Int = 60) {
        // Lê o token salvo pelo ShieldActionExtension
        let unlockUntil = (sharedDefaults?.double(forKey: "pppix_unlocked_until") ?? 0)
        let alreadyUnlocked = unlockUntil > Date().timeIntervalSince1970

        if alreadyUnlocked {
            // ShieldActionExtension já removeu o token — só confirma o timestamp
            return
        }

        // Fallback: se chamado sem unlock prévio do ShieldAction (caminho inesperado)
        // remove todos os apps por segurança
        store.shield.applications = nil
        let newUntil = Date().timeIntervalSince1970 + Double(seconds)
        sharedDefaults?.set(newUntil, forKey: "pppix_unlocked_until")
        sharedDefaults?.synchronize()
    }

    func reblockOnBackground() {
        if !isCurrentlyUnlocked() {
            applyShield()
        }
        // Se ainda está desbloqueado, o timer da notificação (ShieldActionExtension)
        // vai rebloquear quando expirar
    }

    // MARK: - Reblock após senha correta
    // Chamado pelo UnlockPasswordView após senha 1 ou 3 ser aceita
    func reblockAfterPasswordVerified() {
        // Não rebloqueia imediatamente — o ShieldAction já agendou o reblock em 60s
        // O usuário precisa desse tempo para usar o app
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
    func reblockAfterPasswordVerified() {}
    var hasBlockedApps: Bool { false }
}

#endif
