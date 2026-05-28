import Foundation
import UserNotifications
import SwiftUI

#if !targetEnvironment(simulator)
import FamilyControls
import ManagedSettings
import DeviceActivity

@MainActor
final class ScreenTimeManager: ObservableObject {

    static let shared = ScreenTimeManager()
    private init() {}

    // Store com nome — essencial para a ShieldConfigurationExtension reconhecer
    let store = ManagedSettingsStore(named: ManagedSettingsStore.Name("pppix"))
    @Published var isAuthorized = false
    @Published var currentSelection = FamilyActivitySelection()

    private let sharedDefaults = UserDefaults(suiteName: "group.tech.pppix.app")
    private let activityCenter = DeviceActivityCenter()

    static let selectionKey        = "pppix_activity_selection"
    static let unlockedUntilKey    = "pppix_unlocked_until"
    static let activityName        = DeviceActivityName("pppix.reblock")

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
            // Verificação síncrona ao abrir o app — aplica shield se necessário
            syncCheckAndReblock()
        }
    }

    // Verificação síncrona ANTES de qualquer async — padrão do Habit Doom
    func syncCheckAndReblock() {
        guard isAuthorized else { return }
        let unlockedUntil = sharedDefaults?.double(forKey: Self.unlockedUntilKey) ?? 0
        let isUnlocked = unlockedUntil > Date().timeIntervalSince1970
        if !isUnlocked {
            // Não está desbloqueado — aplica shield imediatamente
            applyShield()
        }
    }

    // MARK: - Seleção de apps

    func applySelection(_ selection: FamilyActivitySelection) {
        currentSelection = selection
        saveSelection(selection)
        // Aplica shield imediatamente
        applyShield()
    }

    // Aplica o shield — 3 propriedades obrigatórias (apps + categorias + webdomains)
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

    // MARK: - Desbloqueio temporário após senha

    private var reblockWorkItem: DispatchWorkItem?

    func unlockTemporarily(seconds: Int = 60) {
        let until = Date().timeIntervalSince1970 + Double(seconds)
        sharedDefaults?.set(until, forKey: Self.unlockedUntilKey)
        sharedDefaults?.synchronize()

        // Remove shield para o usuário acessar o app protegido
        removeShield()

        // Cancela reblock anterior se existir
        reblockWorkItem?.cancel()

        // Agenda reblock após X segundos via DispatchQueue — simples e confiável
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.applyShield()
            self.sharedDefaults?.removeObject(forKey: Self.unlockedUntilKey)
            self.sharedDefaults?.synchronize()
        }
        reblockWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(seconds), execute: workItem)
    }

    // Chamado quando PPPIX vai para background — rebloqueia imediatamente
    func reblockOnBackground() {
        let unlockedUntil = sharedDefaults?.double(forKey: Self.unlockedUntilKey) ?? 0
        let isUnlocked = unlockedUntil > Date().timeIntervalSince1970
        guard isUnlocked else { return }

        // Cancela o timer de 1 minuto e rebloqueia agora
        reblockWorkItem?.cancel()
        reblockWorkItem = nil
        applyShield()
        sharedDefaults?.removeObject(forKey: Self.unlockedUntilKey)
        sharedDefaults?.synchronize()
    }

    func unblockAll() { unlockTemporarily(seconds: 60) }
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
    func unlockTemporarily(seconds: Int = 60) {}
    func unblockAll() {}
    func reblockAfterUnlock() {}
    func syncCheckAndReblock() {}
    func loadSavedSelection() {}
    var hasBlockedApps: Bool { false }
}

#endif
