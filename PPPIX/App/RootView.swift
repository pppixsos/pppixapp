import SwiftUI

struct RootView: View {

    @StateObject private var session = SessionManager.shared
    @State private var showAlertDetail: Int? = nil
    @State private var showUnlockScreen = false
    
    private let sharedDefaults = UserDefaults(suiteName: "group.tech.pppix.app")
    private let unlockTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if session.isLoggedIn {
                HomeView()
            } else {
                LoginView()
            }
        }
        .fullScreenCover(isPresented: $showUnlockScreen) {
            LockScreenView {
                showUnlockScreen = false
                // Re-bloqueia após 60 segundos
                DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
                    ScreenTimeManager.shared.reblockFromSaved()
                }
            }
        }
        .onReceive(unlockTimer) { _ in
            checkUnlockRequest()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openUnlockScreen)) { _ in
            showUnlockScreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openAlertDetail)) { notif in
            if let alertId = notif.userInfo?["alert_id"] as? Int {
                showAlertDetail = alertId
            }
        }
        .sheet(item: $showAlertDetail) { alertId in
            AlertDetailView(alertId: alertId)
        }
    }
    
    private func checkUnlockRequest() {
        guard let requested = sharedDefaults?.bool(forKey: "pppix_unlock_requested"),
              requested == true else { return }
        
        let timestamp = sharedDefaults?.double(forKey: "pppix_unlock_timestamp") ?? 0
        let age = Date().timeIntervalSince1970 - timestamp
        
        // Só abre se a requisição for recente (menos de 5 segundos)
        guard age < 5 else {
            sharedDefaults?.set(false, forKey: "pppix_unlock_requested")
            return
        }
        
        sharedDefaults?.set(false, forKey: "pppix_unlock_requested")
        sharedDefaults?.synchronize()
        
        if !showUnlockScreen {
            showUnlockScreen = true
        }
    }
}

extension Int: @retroactive Identifiable {
    public var id: Int { self }
}
