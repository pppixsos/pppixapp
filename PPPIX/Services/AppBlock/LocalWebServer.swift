import Foundation
import Network
import UIKit

final class LocalWebServer {

    static let shared = LocalWebServer()
    private init() {}

    private var listener: NWListener?
    private let port: UInt16 = 8765
    private var profiles: [String: Data] = [:]
    private let queue = DispatchQueue(label: "tech.pppix.server", qos: .background)

    func startIfNeeded() {
        guard listener == nil else { return }

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        guard let nwPort = NWEndpoint.Port(rawValue: port),
              let l = try? NWListener(using: params, on: nwPort) else { return }

        listener = l
        listener?.newConnectionHandler = { [weak self] conn in
            self?.handle(connection: conn)
        }
        listener?.start(queue: queue)
    }

    func serveProfile(for app: InstalledApp) -> URL {
        let token = UUID().uuidString.prefix(8)
        let path = "/p/\(token)"
        profiles[path] = buildMobileConfig(for: app, uuid: UUID().uuidString)
        // Pequeno delay para o servidor estar pronto
        return URL(string: "http://127.0.0.1:\(port)\(path)")!
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self,
                  let data,
                  let req = String(data: data, encoding: .utf8),
                  let path = req.components(separatedBy: "\r\n").first?
                                .components(separatedBy: " ").dropFirst().first,
                  let body = self.profiles[path]
            else {
                connection.cancel()
                return
            }

            let header = "HTTP/1.1 200 OK\r\nContent-Type: application/x-apple-aspen-config\r\nContent-Disposition: attachment; filename=\"pppix.mobileconfig\"\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            var resp = header.data(using: .utf8)!
            resp.append(body)
            connection.send(content: resp, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private func buildMobileConfig(for app: InstalledApp, uuid: String) -> Data {
        let deepLink = "pppix://unlock?bundle=\(app.id)&name=\(app.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? app.name)"

        // Ícone em base64 — se não tiver ícone, usar string vazia (iOS usa ícone padrão)
        // Sem ícone customizado — iOS usa screenshot como ícone do web clip
        let iconTag = ""

        let xml = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>PayloadContent</key>
    <array>
        <dict>
            <key>FullScreen</key>
            <true/>
            \(iconTag)
            <key>IsRemovable</key>
            <true/>
            <key>Label</key>
            <string>\(app.name)</string>
            <key>PayloadDescription</key>
            <string>Proteção PPPIX para \(app.name)</string>
            <key>PayloadDisplayName</key>
            <string>\(app.name)</string>
            <key>PayloadIdentifier</key>
            <string>tech.pppix.webclip.\(app.id).\(uuid)</string>
            <key>PayloadType</key>
            <string>com.apple.webClip.managed</string>
            <key>PayloadUUID</key>
            <string>\(UUID().uuidString)</string>
            <key>PayloadVersion</key>
            <integer>1</integer>
            <key>URL</key>
            <string>\(deepLink)</string>
        </dict>
    </array>
    <key>PayloadDescription</key>
    <string>Protege \(app.name) com senha PPPIX</string>
    <key>PayloadDisplayName</key>
    <string>PPPIX – \(app.name)</string>
    <key>PayloadIdentifier</key>
    <string>tech.pppix.profile.\(app.id).\(uuid)</string>
    <key>PayloadRemovalDisallowed</key>
    <false/>
    <key>PayloadType</key>
    <string>Configuration</string>
    <key>PayloadUUID</key>
    <string>\(uuid)</string>
    <key>PayloadVersion</key>
    <integer>1</integer>
</dict>
</plist>
"""
        return xml.data(using: .utf8) ?? Data()
    }
}
