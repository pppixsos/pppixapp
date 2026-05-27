import SwiftUI

// Int conformance to Identifiable for sheet(item:)
extension Int: @retroactive Identifiable {
    public var id: Int { self }
}

struct RootView: View {

    @StateObject private var session = SessionManager.shared
    @State private var showAlertDetail: Int? = nil
    @State private var showLockScreen = false
    @State private var unlockBundleId = ""
    @State private var unlockAppName = "App"

    var body: some View {
        Group {
            if session.isLoggedIn {
                HomeView()
            } else {
                LoginView()
            }
        }
        .fullScreenCover(isPresented: $showLockScreen) {
            LockScreenView(
                appName: unlockAppName,
                onUnlocked: {
                    showLockScreen = false
                    if !unlockBundleId.isEmpty {
                        #if !targetEnvironment(simulator)
                        AppBlockManager.shared.openRealApp(bundleId: unlockBundleId)
                        #endif
                    }
                }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .openAlertDetail)) { notif in
            if let alertId = notif.userInfo?["alert_id"] as? Int {
                showAlertDetail = alertId
            }
        }
        .sheet(item: $showAlertDetail) { alertId in
            AlertDetailView(alertId: alertId)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openUnlockScreen)) { notification in
            unlockBundleId = notification.userInfo?["bundleId"] as? String ?? ""
            unlockAppName = (notification.userInfo?["appName"] as? String ?? "App")
                .removingPercentEncoding ?? "App"
            showLockScreen = true
        }
    }
}
