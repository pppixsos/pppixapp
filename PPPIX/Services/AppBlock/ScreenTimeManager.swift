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

    // MARK: - Unlock individual (chamado APÓS senha correta)

    func unlockSingleApp(reblockAfterSeconds: Int = 10) {
        // Lê o token do app que o usuário tocou (salvo pelo ShieldActionExtension)
        guard let tokenData = sharedDefaults?.data(forKey: "pppix_single_app_token_data"),
              let singleToken = try? JSONDecoder().decode(ApplicationToken.self, from: tokenData) else {
            // Fallback: remove todos os shields por 10s
            unlockAll(reblockAfterSeconds: reblockAfterSeconds)
            return
        }

        // Remove APENAS o token do app tocado
        var remaining = currentSelection.applicationTokens
        remaining.remove(singleToken)
        store.shield.applications = remaining.isEmpty ? nil : remaining
        // Categorias e webDomains permanecem bloqueados

        // Salva timestamp do unlock
        let until = Date().timeIntervalSince1970 + Double(reblockAfterSeconds)
        sharedDefaults?.set(until, forKey: "pppix_unlocked_until")
        sharedDefaults?.synchronize()

        // Agenda reblock via DeviceActivity (mais confiável que DispatchQueue em background)
        scheduleReblock(afterSeconds: reblockAfterSeconds)
    }

    private func unlockAll(reblockAfterSeconds: Int) {
        store.shield.applications = nil
        let until = Date().timeIntervalSince1970 + Double(reblockAfterSeconds)
        sharedDefaults?.set(until, forKey: "pppix_unlocked_until")
        sharedDefaults?.synchronize()
        scheduleReblock(afterSeconds: reblockAfterSeconds)
    }

    // MARK: - Reblock via DeviceActivityCenter
    // Mais confiável que DispatchQueue — sobrevive ao app ser morto

    private func scheduleReblock(afterSeconds seconds: Int) {
        let center = DeviceActivityCenter()

        // Para qualquer monitoramento anterior de reblock
        center.stopMonitoring([DeviceActivityName("pppix.reblock")])

        let now = Date()
        let reblockAt = now.addingTimeInterval(Double(seconds))

        let cal = Calendar.current
        let startComponents = cal.dateComponents([.hour, .minute, .second], from: now)
        let endComponents = cal.dateComponents([.hour, .minute, .second], from: reblockAt)

        let schedule = DeviceActivitySchedule(
            intervalStart: startComponents,
            intervalEnd: endComponents,
            repeats: false
        )

        try? center.startMonitoring(
            DeviceActivityName("pppix.reblock"),
            during: schedule
        )
    }

    func reblockOnBackground() {
        if !isCurrentlyUnlocked() {
            applyShield()
        }
        // Se ainda desbloqueado, o DeviceActivityMonitor vai rebloquear quando o tempo acabar
    }

    // Compatibilidade
    func unlockTemporarily(seconds: Int = 10) { unlockSingleApp(reblockAfterSeconds: seconds) }
    func unblockAll() { unlockSingleApp(reblockAfterSeconds: 10) }
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
    func unlockSingleApp(reblockAfterSeconds: Int = 10) {}
    func unlockTemporarily(seconds: Int = 10) {}
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
