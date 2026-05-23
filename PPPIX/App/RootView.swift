import SwiftUI

struct RootView: View {

    @StateObject private var session = SessionManager.shared
    @State private var showAlertDetail: Int? = nil

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
        .sheet(item: $showAlertDetail) { alertId in
            AlertDetailView(alertId: alertId)
        }
    }
}

// Int conformance to Identifiable for sheet(item:)
extension Int: @retroactive Identifiable {
    public var id: Int { self }
}
