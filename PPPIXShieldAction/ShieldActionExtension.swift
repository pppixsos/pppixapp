import ManagedSettings
import Foundation

class ShieldActionExtension: ShieldActionDelegate {

    override func handle(action: ShieldAction, for application: ApplicationToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        openUnlockURL(completionHandler: completionHandler)
    }

    override func handle(action: ShieldAction, for webDomain: WebDomainToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        openUnlockURL(completionHandler: completionHandler)
    }

    override func handle(action: ShieldAction, for category: ActivityCategoryToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        openUnlockURL(completionHandler: completionHandler)
    }

    private func openUnlockURL(completionHandler: @escaping (ShieldActionResponse) -> Void) {
        guard let url = URL(string: "pppix://unlock") else {
            completionHandler(.defer)
            return
        }
        extensionContext?.open(url) { _ in
            completionHandler(.defer)
        }
    }
}
