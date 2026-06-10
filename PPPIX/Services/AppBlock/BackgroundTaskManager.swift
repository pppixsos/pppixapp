import BackgroundTasks
import UIKit
import UserNotifications

final class BackgroundTaskManager: @unchecked Sendable {

    static let shared = BackgroundTaskManager()
    private init() {}

    private let appRefreshIdentifier = "tech.pppix.app.refresh"
    private let processingIdentifier = "tech.pppix.app.processing"

    // MARK: - Register

    func registerTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: appRefreshIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handleAppRefresh(task: refreshTask)
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: processingIdentifier,
            using: nil
        ) { task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handleProcessing(task: processingTask)
        }
    }

    // MARK: - Schedule

    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: appRefreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    func scheduleProcessing() {
        let request = BGProcessingTaskRequest(identifier: processingIdentifier)
        request.requiresNetworkConnectivity = true
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: - Handlers

    private func handleAppRefresh(task: BGAppRefreshTask) {
        scheduleAppRefresh()

        // BGAppRefreshTask não é Sendable — não pode ser capturado por Task{}
        // Usando DispatchQueue para evitar o problema de concorrência Swift 6
        var expired = false
        task.expirationHandler = {
            expired = true
            task.setTaskCompleted(success: false)
        }

        DispatchQueue.global(qos: .background).async {
            guard !expired else { return }
            guard SessionManager.shared.isLoggedIn else {
                task.setTaskCompleted(success: true)
                return
            }

            // Verificar alertas de forma síncrona via semáforo
            let semaphore = DispatchSemaphore(value: 0)
            Task {
                defer { semaphore.signal() }
                guard !expired else { return }
                await self.checkAndNotifyAlerts()
            }
            semaphore.wait()

            if !expired {
                task.setTaskCompleted(success: true)
            }
        }
    }

    private func checkAndNotifyAlerts() async {
        guard let alerts = try? await APIClient.shared.getReceivedAlerts() else { return }

        let myEmail = SessionManager.shared.userEmail
        let shown = AlertDeduplicator.shared.shownIds
        let cutoff = Date().addingTimeInterval(-10 * 60)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        guard let a = alerts.first(where: {
            let isMine = !myEmail.isEmpty && $0.sender_email.lowercased() == myEmail.lowercased()
            let s = $0.status.lowercased()
            let date = iso.date(from: $0.created_at) ?? .distantPast
            return !isMine && s != "cancelled" && !shown.contains($0.id) && date > cutoff
        }) else { return }

        AlertDeduplicator.shared.markShown(a.id)
        try? await APIClient.shared.markAlertRead(id: a.id)

        let nc = UNMutableNotificationContent()
        let name = a.sender_name.isEmpty
            ? (a.sender_email.components(separatedBy: "@").first ?? "Contato")
            : a.sender_name
        nc.title = "🚨 Alerta de Emergência"
        nc.body = "\(name) pode estar em perigo! Toque para ver detalhes."
        nc.interruptionLevel = .critical
        nc.categoryIdentifier = "PPPIX_EMERGENCY"
        nc.sound = Bundle.main.url(forResource: "sirene", withExtension: "caf") != nil
            ? UNNotificationSound(named: UNNotificationSoundName(rawValue: "sirene.caf"))
            : UNNotificationSound.defaultCritical
        nc.userInfo = [
            "alert_id": String(a.id),
            "alert_type": a.alert_type,
            "sender_email": a.sender_email,
            "sender_name": a.sender_name,
            "latitude": a.latitude ?? "",
            "longitude": a.longitude ?? ""
        ]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let req = UNNotificationRequest(identifier: "pppix_alert_\(a.id)", content: nc, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(req)
    }

    private func handleProcessing(task: BGProcessingTask) {
        scheduleProcessing()
        task.setTaskCompleted(success: true)
    }

    // MARK: - App lifecycle

    func appDidEnterBackground() {
        DispatchQueue.main.async {
            self.scheduleAppRefresh()
            self.scheduleProcessing()
        }
    }
}
