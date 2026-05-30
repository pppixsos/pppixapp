import BackgroundTasks
import UIKit

/// Equivalente ao AppMonitorService.kt do Android.
/// Mantém o app vivo via BGTaskScheduler + Silent Push + Background App Refresh.
@MainActor
final class BackgroundTaskManager {

    static let shared = BackgroundTaskManager()
    private init() {}

    private let appRefreshIdentifier = "tech.pppix.app.refresh"
    private let processingIdentifier = "tech.pppix.app.processing"

    // MARK: - Register (chamar no didFinishLaunching)

    func registerTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: appRefreshIdentifier,
            using: nil
        ) { task in
            self.handleAppRefresh(task: task as! BGAppRefreshTask)
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: processingIdentifier,
            using: nil
        ) { task in
            self.handleProcessing(task: task as! BGProcessingTask)
        }
    }

    // MARK: - Schedule (chamar quando app vai para background)

    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: appRefreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 min
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
        scheduleAppRefresh() // Re-agenda imediatamente

        let taskOp = Task {
            // Verifica se o app ainda está logado e token ainda é válido
            if SessionManager.shared.isLoggedIn {
                _ = try? await APIClient.shared.getMe()
            }
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            taskOp.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    private func handleProcessing(task: BGProcessingTask) {
        scheduleProcessing()
        task.setTaskCompleted(success: true)
    }

    // MARK: - App lifecycle hooks (chamar no SceneDelegate/App)

    func appDidEnterBackground() {
        scheduleAppRefresh()
        scheduleProcessing()
    }
}
