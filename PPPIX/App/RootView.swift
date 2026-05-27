import SwiftUI

struct RootView: View {

    @StateObject private var session = SessionManager.shared
    @State private var showAlertDetail: Int? = nil
    @State private var showUnlockScreen = false

    var body: some View {
        Group {
            if session.isLoggedIn {
                HomeView()
            } else {
                LoginView()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openAlertDetail)) { notif in
            if let alertId = notif.userInfo?["alert_id"] as? Int {
                showAlertDetail = alertId
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openUnlockScreen)) { _ in
            // Abre tela de senha quando vem de pppix://unlock
            if session.isLoggedIn {
                showUnlockScreen = true
            }
        }
        .sheet(item: $showAlertDetail) { alertId in
            AlertDetailView(alertId: alertId)
        }
        .fullScreenCover(isPresented: $showUnlockScreen) {
            LockScreenView(
                appName: "App Financeiro",
                onUnlocked: {
                    showUnlockScreen = false
                    // Desbloqueia temporariamente e rebloqueia após 60 segundos
                    #if !targetEnvironment(simulator)
                    ScreenTimeManager.shared.unblockAll()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
                        ScreenTimeManager.shared.reblockFromSaved()
                    }
                    #endif
                }
            )
        }
    }
}

extension Int: @retroactive Identifiable {
    public var id: Int { self }
}
