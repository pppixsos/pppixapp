import ManagedSettings
import Foundation

// Esta extensão é chamada quando o usuário toca no botão da tela shield
// Ela sinaliza o app principal para abrir a tela de senha via UserDefaults compartilhado
class ShieldActionExtension: ShieldActionDelegate {

    private let sharedDefaults = UserDefaults(suiteName: "group.tech.pppix.app")

    override func handle(action: ShieldAction,
                         for application: ApplicationToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        handleAction(completionHandler: completionHandler)
    }

    override func handle(action: ShieldAction,
                         for webDomain: WebDomainToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        handleAction(completionHandler: completionHandler)
    }

    override func handle(action: ShieldAction,
                         for category: ActivityCategoryToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        handleAction(completionHandler: completionHandler)
    }

    private func handleAction(completionHandler: @escaping (ShieldActionResponse) -> Void) {
        // Sinaliza o app principal via UserDefaults compartilhado
        sharedDefaults?.set(true, forKey: "pppix_show_password_screen")
        sharedDefaults?.set(Date().timeIntervalSince1970, forKey: "pppix_password_request_time")
        sharedDefaults?.synchronize()

        // .defer mantém o app bloqueado — o PPPIX vai desbloquear depois da senha
        // O app principal monitora o UserDefaults e abre a tela de senha
        // Após senha correta, chama ScreenTimeManager.unblockAll() e abre via URL scheme
        completionHandler(.defer)
    }
}
