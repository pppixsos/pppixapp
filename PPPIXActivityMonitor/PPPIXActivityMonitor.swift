import DeviceActivity
import ManagedSettings

/// Target: PPPIXActivityMonitor
/// Bundle ID: tech.pppix.app.monitor
///
/// Adicionar no Xcode:
///   File → New → Target → Device Activity Monitor Extension
///   Product Name: PPPIXActivityMonitor
///
/// Capabilities do target:
///   - Family Controls
///   - App Groups: group.tech.pppix.app

class PPPIXActivityMonitor: DeviceActivityMonitor {

    private let store = ManagedSettingsStore(named: .init("pppix"))
    private let sharedDefaults = UserDefaults(suiteName: "group.tech.pppix.app")

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        // Proteção ativa
        sharedDefaults?.set(true, forKey: "pppix_monitor_active")
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        // Re-agenda para continuar ativo
        sharedDefaults?.set(false, forKey: "pppix_monitor_active")
    }

    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        super.eventDidReachThreshold(event, activity: activity)
        // O ManagedSettings já bloqueia automaticamente.
        // O ShieldConfiguration mostra a UI customizada.
    }

    override func intervalWillStartWarning(for activity: DeviceActivityName) {
        super.intervalWillStartWarning(for: activity)
    }

    override func intervalWillEndWarning(for activity: DeviceActivityName) {
        super.intervalWillEndWarning(for: activity)
    }
}
