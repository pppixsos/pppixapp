import Foundation
import UIKit

// Representa um app instalado no iPhone
struct InstalledApp: Identifiable, Codable {
    let id: String       // bundle ID
    let name: String
    let urlScheme: String
    let iconName: String // nome do asset local
    var isBlocked: Bool
    var profileInstalled: Bool

    // Ícone como Data — carregado em runtime
    var iconData: Data? {
        if let img = UIImage(named: iconName) { return img.pngData() }
        return nil
    }
}

// Catálogo de apps financeiros/utilitários populares no Brasil
// com seus URL schemes para verificar se estão instalados
struct AppCatalog {
    static let all: [(id: String, name: String, scheme: String, icon: String)] = [
        // Bancos
        ("com.itau.iphone",                 "Itaú",              "itauaplicativo://",    "app_itau"),
        ("com.bradesco.Bradesco",           "Bradesco",          "bradesco://",          "app_bradesco"),
        ("com.bb.bolsodigital",             "Banco do Brasil",   "bbdigi://",            "app_bb"),
        ("com.santander.SantanderBrasil",   "Santander",         "santander://",         "app_santander"),
        ("com.caixa.caixatem",              "Caixa Tem",         "caixatemapp://",       "app_caixa"),
        ("com.nubank.app",                  "Nubank",            "nubank://",            "app_nubank"),
        ("com.c6bank.ios",                  "C6 Bank",           "c6bank://",            "app_c6bank"),
        ("com.inter.Inter",                 "Inter",             "interapp://",          "app_inter"),
        ("br.com.sicredi.sicredi",          "Sicredi",           "sicredi://",           "app_sicredi"),
        ("com.picpay.ios",                  "PicPay",            "picpay://",            "app_picpay"),
        ("com.mercadopago.ios",             "Mercado Pago",      "mercadopago://",       "app_mercadopago"),
        ("com.xp.minha-conta",              "XP",                "xpapp://",             "app_xp"),
        ("com.btgpactual.digital",          "BTG Pactual",       "btgpactual://",        "app_btg"),
        // Pagamentos
        ("com.apple.Passbook",              "Apple Wallet",      "shoebox://",           "app_wallet"),
        ("br.com.pagaleve.app",             "Pagaleve",          "pagaleve://",          "app_pagaleve"),
        // Outros financeiros
        ("com.guiabolso.ios",               "Guiabolso",         "guiabolso://",         "app_guiabolso"),
        ("com.neon.Neon",                   "Neon",              "neon://",              "app_neon"),
        ("br.com.original.original",        "Original",          "original://",          "app_original"),
        ("com.agibank.app",                 "Agibank",           "agibank://",           "app_agibank"),
        ("com.sofisa.sofisa",               "Sofisa",            "sofisa://",            "app_sofisa"),
        // Redes sociais / comunicação
        ("com.facebook.Facebook",           "Facebook",          "fb://",                "app_facebook"),
        ("com.instagram.Instagram",         "Instagram",         "instagram://",         "app_instagram"),
        ("com.burbn.instagram",             "Instagram",         "instagram://",         "app_instagram"),
        ("net.whatsapp.WhatsApp",           "WhatsApp",          "whatsapp://",          "app_whatsapp"),
        ("com.toyopagroup.picaboo",         "Snapchat",          "snapchat://",          "app_snapchat"),
        ("com.atebits.Tweetie2",            "Twitter/X",         "twitter://",           "app_twitter"),
        ("com.zhiliaoapp.musically",        "TikTok",            "tiktok://",            "app_tiktok"),
        ("com.hammerandchisel.discord",     "Discord",           "discord://",           "app_discord"),
        ("com.toyopagroup.picaboo",         "Telegram",          "tg://",                "app_telegram"),
        // Outros
        ("com.google.Maps",                 "Google Maps",       "comgooglemaps://",     "app_gmaps"),
        ("com.ubercab.UberClient",          "Uber",              "uber://",              "app_uber"),
        ("com.99app.client",                "99",                "taxis99://",           "app_99"),
        ("com.ifood.app",                   "iFood",             "ifood://",             "app_ifood"),
        ("com.rappi.app",                   "Rappi",             "rappi://",             "app_rappi"),
    ]

    static func installedApps() -> [InstalledApp] {
        var seen = Set<String>()
        var result: [InstalledApp] = []

        for entry in all {
            guard !seen.contains(entry.id) else { continue }
            guard let url = URL(string: entry.scheme),
                  UIApplication.shared.canOpenURL(url) else { continue }
            seen.insert(entry.id)
            result.append(InstalledApp(
                id: entry.id,
                name: entry.name,
                urlScheme: entry.scheme,
                iconName: entry.icon,
                isBlocked: false,
                profileInstalled: false
            ))
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
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
        Task.detached(priority: .userInitiated) {
            let apps = AppCatalog.installedApps()
            await MainActor.run {
                self.installedApps = apps
                self.isLoadingApps = false
            }
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
        // Abrir pelo URL scheme do app
        if let app = blockedApps.first(where: { $0.id == bundleId }),
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
