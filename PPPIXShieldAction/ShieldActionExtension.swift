import ManagedSettings

class ShieldActionExtension: ShieldActionDelegate {

    override func handle(action: ShieldAction, for application: Application, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        switch action {
        case .primaryButtonPressed:
            // Abre PPPIX direto na tela de senha
            if let url = URL(string: "pppix://unlock") {
                self.open(url)
            }
            completionHandler(.defer)
        case .secondaryButtonPressed:
            completionHandler(.defer)  // .defer mantém o shield aberto em vez de fechar
        @unknown default:
            completionHandler(.defer)
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
            completionHandler(.defer)
        }
    }
}
