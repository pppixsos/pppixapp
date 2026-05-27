import ManagedSettings

class ShieldActionExtension: ShieldActionDelegate {

    override func handle(action: ShieldAction, for application: Application, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        switch action {
        case .primaryButtonPressed:
            // Abre o PPPIX direto na tela de senha de desbloqueio
            if let url = URL(string: "pppix://unlock") {
                self.open(url)
            }
            completionHandler(.defer)
        case .secondaryButtonPressed:
            completionHandler(.close)
        @unknown default:
            completionHandler(.close)
        }
    }

    override func handle(action: ShieldAction, for webDomain: WebDomain, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        switch action {
        case .primaryButtonPressed:
            if let url = URL(string: "pppix://unlock") {
                self.open(url)
            }
            completionHandler(.defer)
        default:
            completionHandler(.close)
        }
    }
}
