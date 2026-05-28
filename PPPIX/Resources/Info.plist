import ManagedSettings
import Foundation

class ShieldActionExtension: ShieldActionDelegate {

    private let sharedDefaults = UserDefaults(suiteName: "group.tech.pppix.app")

    override func handle(action: ShieldAction,
                         for application: ApplicationToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        requestUnlock(completionHandler: completionHandler)
    }

    override func handle(action: ShieldAction,
                         for webDomain: WebDomainToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        requestUnlock(completionHandler: completionHandler)
    }

    override func handle(action: ShieldAction,
                         for category: ActivityCategoryToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        requestUnlock(completionHandler: completionHandler)
    }

    private func requestUnlock(completionHandler: @escaping (ShieldActionResponse) -> Void) {
        sharedDefaults?.set(true, forKey: "pppix_show_password_screen")
        sharedDefaults?.set(Date().timeIntervalSince1970, forKey: "pppix_password_request_time")
        sharedDefaults?.synchronize()

        // Abre o PPPIX via URL scheme — iOS abre o app registrado com esse scheme
        if let url = URL(string: "pppix://unlock") {
            completionHandler(.open(url))
        } else {
            completionHandler(.close)
        }
    }
}
