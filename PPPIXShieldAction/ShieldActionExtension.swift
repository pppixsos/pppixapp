import ManagedSettings
import Foundation

class ShieldActionExtension: ShieldActionDelegate {

    private let sharedDefaults = UserDefaults(suiteName: "group.tech.pppix.app")

    override func handle(action: ShieldAction, for application: Application, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        requestUnlock()
        completionHandler(.defer)
    }

    override func handle(action: ShieldAction, for webDomain: WebDomain, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        requestUnlock()
        completionHandler(.defer)
    }

    private func requestUnlock() {
        sharedDefaults?.set(true, forKey: "pppix_unlock_requested")
        sharedDefaults?.set(Date().timeIntervalSince1970, forKey: "pppix_unlock_timestamp")
        sharedDefaults?.synchronize()
    }
}
