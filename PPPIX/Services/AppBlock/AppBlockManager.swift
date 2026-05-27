import Foundation
import UIKit

struct InstalledApp: Identifiable, Codable {
    let id: String
    let name: String
    let urlScheme: String
    var isBlocked: Bool
    var profileInstalled: Bool
}

// Lista fixa de apps populares no Brasil — mostrada sempre, independente de estar instalado
// O usuário escolhe o app dele e o atalho é criado com o ícone correto
struct AppCatalog {
    static let all: [InstalledApp] = [
        // Bancos tradicionais
        InstalledApp(id: "com.itau.iphone",               name: "Itaú",             urlScheme: "itauaplicativo://", isBlocked: false, profileInstalled: false),
        InstalledApp(id: "com.bradesco.app",              name: "Bradesco",          urlScheme: "bradesco://",       isBlocked: false, profileInstalled: false),
        InstalledApp(id: "com.bb.bolsodigital",           name: "Banco do Brasil",   urlScheme: "bbdigi://",         isBlocked: false, profileInstalled: false),
        InstalledApp(id: "com.santander.app",             name: "Santander",         urlScheme: "santander://",      isBlocked: false, profileInstalled: false),
        InstalledApp(id: "com.caixa.app",                 name: "Caixa",             urlScheme: "caixatem://",       isBlocked: false, profileInstalled: false),
        // Bancos digitais
        InstalledApp(id: "com.nubank.app",                name: "Nubank",            urlScheme: "nubank://",         isBlocked: false, profileInstalled: false),
        InstalledApp(id: "com.c6bank.ios",                name: "C6 Bank",           urlScheme: "c6bank://",         isBlocked: false, profileInstalled: false),
        InstalledApp(id: "com.inter.Inter",               name: "Inter",             urlScheme: "interapp://",       isBlocked: false, profileInstalled: false),
        InstalledApp(id: "com.neon.Neon",                 name: "Neon",              urlScheme: "neon://",           isBlocked: false, profileInstalled: false),
        InstalledApp(id: "com.original.app",              name: "Original",          urlScheme: "original://",       isBlocked: false, profileInstalled: false),
        InstalledApp(id: "br.com.sicredi.app",            name: "Sicredi",           urlScheme: "sicredi://",        isBlocked: false, profileInstalled: false),
        InstalledApp(id: "com.agibank.app",               name: "Agibank",           urlScheme: "agibank://",        isBlocked: false, profileInstalled: false),
        // Pagamentos
        InstalledApp(id: "com.picpay.ios",                name: "PicPay",            urlScheme: "picpay://",         isBlocked: false, profileInstalled: false),
        InstalledApp(id: "com.mercadopago.ios",           name: "Mercado Pago",      urlScheme: "mercadopago://",    isBlocked: false, profileInstalled: false),
        InstalledApp(id: "com.xp.app",                    name: "XP",                urlScheme: "xpapp://",          isBlocked: false, profileInstalled: false),
        InstalledApp(id: "com.btgpactual.app",            name: "BTG Pactual",       urlScheme: "btgpactual://",     isBlocked: false, profileInstalled: false),
        // Redes sociais
        InstalledApp(id: "com.facebook.Facebook",         name: "Facebook",          urlScheme: "fb://",             isBlocked: false, profileInstalled: false),
        InstalledApp(id: "com.burbn.instagram",           name: "Instagram",         urlScheme: "instagram://",      isBlocked: false, profileInstalled: false),
        InstalledApp(id: "net.whatsapp.WhatsApp",         name: "WhatsApp",          urlScheme: "whatsapp://",       isBlocked: false, profileInstalled: false),
        InstalledApp(id: "com.zhiliaoapp.musically",      name: "TikTok",            urlScheme: "tiktok://",         isBlocked: false, profileInstalled: false),
        InstalledApp(id: "com.atebits.Tweetie2",          name: "X (Twitter)",       urlScheme: "twitter://",        isBlocked: false, profileInstalled: false),
        InstalledApp(id: "com.hammerandchisel.discord",   name: "Discord",           urlScheme: "discord://",        isBlocked: false, profileInstalled: false),
        InstalledApp(id: "ph.telegra.Telegraph",          name: "Telegram",          urlScheme: "tg://",             isBlocked: false, profileInstalled: false),
        // Outros
        InstalledApp(id: "com.ubercab.UberClient",        name: "Uber",              urlScheme: "uber://",           isBlocked: false, profileInstalled: false),
        InstalledApp(id: "com.99app.client",              name: "99",                urlScheme: "taxis99://",        isBlocked: false, profileInstalled: false),
        InstalledApp(id: "com.ifood.app",                 name: "iFood",             urlScheme: "ifood://",          isBlocked: false, profileInstalled: false),
        InstalledApp(id: "com.rappi.app",                 name: "Rappi",             urlScheme: "rappi://",          isBlocked: false, profileInstalled: false),
    ]
}

@MainActor
final class AppBlockManager: ObservableObject {

    static let shared = AppBlockManager()
    private init() { loadBlockedApps() }

    private let sharedDefaults = UserDefaults(suiteName: "group.tech.pppix.app")
    private let server = LocalWebServer.shared

    @Published var installedApps: [InstalledApp] = []
    @Published var blockedApps: [InstalledApp] = []
    @Published var isLoadingApps = false

    func loadInstalledApps() {
        guard installedApps.isEmpty else { return }
        isLoadingApps = true
        // Mostrar lista completa — usuário escolhe o app dele
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.installedApps = AppCatalog.all
            self.isLoadingApps = false
        }
    }

    func blockApp(_ app: InstalledApp, completion: @escaping (Bool) -> Void) {
        server.startIfNeeded()
        let profileURL = server.serveProfile(for: app)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            UIApplication.shared.open(profileURL) { [weak self] success in
                self?.saveBlockedApp(app)
                completion(success)
            }
        }
    }

    func unblockApp(_ app: InstalledApp) {
        removeBlockedApp(id: app.id)
    }

    func openRealApp(bundleId: String) {
        if let app = (blockedApps + AppCatalog.all).first(where: { $0.id == bundleId }),
           let url = URL(string: app.urlScheme) {
            UIApplication.shared.open(url)
        }
    }

    private func saveBlockedApp(_ app: InstalledApp) {
        var current = blockedApps
        current.removeAll { $0.id == app.id }
        var updated = app
        updated.isBlocked = true
        updated.profileInstalled = true
        current.append(updated)
        blockedApps = current
        persist()
    }

    private func removeBlockedApp(id: String) {
        blockedApps.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(blockedApps) {
            sharedDefaults?.set(data, forKey: "pppix_blocked_apps")
        }
    }

    private func loadBlockedApps() {
        guard let data = sharedDefaults?.data(forKey: "pppix_blocked_apps"),
              let apps = try? JSONDecoder().decode([InstalledApp].self, from: data)
        else { return }
        blockedApps = apps
    }
}
