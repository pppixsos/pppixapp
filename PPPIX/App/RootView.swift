import SwiftUI

struct RootView: View {

    @StateObject private var session = SessionManager.shared
    @State private var showLockScreen = false
    @State private var unlockBundleId = ""
    @State private var unlockAppName = "App"

    var body: some View {
        Group {
            if !session.isLoggedIn {
                LoginView()
            } else {
                MainTabView()
            }
        }
        .fullScreenCover(isPresented: $showLockScreen) {
            LockScreenView(
                appName: unlockAppName,
                onUnlocked: {
                    showLockScreen = false
                    if !unlockBundleId.isEmpty {
                        AppBlockManager.shared.openRealApp(bundleId: unlockBundleId)
                    }
                }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .openUnlockScreen)) { notification in
            unlockBundleId = notification.userInfo?["bundleId"] as? String ?? ""
            unlockAppName = (notification.userInfo?["appName"] as? String ?? "App")
                .removingPercentEncoding ?? "App"
            showLockScreen = true
        }
    }
}
