import ManagedSettings
import Foundation

class ShieldActionExtension: ShieldActionDelegate {

    private let sharedDefaults = UserDefaults(suiteName: "group.tech.pppix.app")

    override func handle(action: ShieldAction, for application: ApplicationToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        requestUnlock(completionHandler: completionHandler)
    }

    override func handle(action: ShieldAction, for webDomain: WebDomainToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        requestUnlock(completionHandler: completionHandler)
    }

    override func handle(action: ShieldAction, for category: ActivityCategoryToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        requestUnlock(completionHandler: completionHandler)
    }

    private func requestUnlock(completionHandler: @escaping (ShieldActionResponse) -> Void) {
        sharedDefaults?.set(true, forKey: "pppix_unlock_requested")
        sharedDefaults?.set(Date().timeIntervalSince1970, forKey: "pppix_unlock_timestamp")
        sharedDefaults?.synchronize()
        completionHandler(.defer)
    }
}
