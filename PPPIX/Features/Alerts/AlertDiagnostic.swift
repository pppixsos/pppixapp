import SwiftUI

/// Log interno visível no app — para debug sem Xcode/Mac
@MainActor
class AlertDiagnosticLog: ObservableObject {
    static let shared = AlertDiagnosticLog()
    private static let key = "pppix_diag_log"
    private static let maxLines = 100

    @Published var lines: [String] = []

    private init() { load() }

    func log(_ msg: String) {
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let line = "[\(ts)] \(msg)"
        print("[PPPIX-DIAG] \(line)")
        lines.insert(line, at: 0)
        if lines.count > Self.maxLines { lines = Array(lines.prefix(Self.maxLines)) }
        save()
    }

    func clear() {
        lines = []
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    private func save() {
        UserDefaults.standard.set(lines, forKey: Self.key)
    }

    private func load() {
        lines = UserDefaults.standard.stringArray(forKey: Self.key) ?? []
    }
}

struct AlertDiagnosticView: View {
    @StateObject private var log = AlertDiagnosticLog.shared
    @Environment(\.dismiss) private var dismiss
    @State private var filter: FilterMode = .all

    enum FilterMode: String, CaseIterable {
        case all = "Tudo"
        case send = "Envio"
        case receive = "Recebimento"
        case error = "Erros"
    }

    var filteredLines: [String] {
        switch filter {
        case .all:     return log.lines
        case .send:    return log.lines.filter { $0.contains("sendSilentAlert") || $0.contains("ENVIAR") || $0.contains("payload") || $0.contains("ENVIADO") }
        case .receive: return log.lines.filter { $0.contains("RECEBER") || $0.contains("FCM") || $0.contains("alerta id=") }
        case .error:   return log.lines.filter { $0.contains("ERRO") || $0.contains("FALHOU") || $0.contains("ABORTADO") || $0.contains("API 4") || $0.contains("API 5") }
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Filtro
                Picker("Filtro", selection: $filter) {
                    ForEach(FilterMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(white: 0.07))

                if filteredLines.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundColor(Color(white: 0.3))
                        Text(log.lines.isEmpty
                             ? "Nenhum log ainda.\n\nUse a senha 3 para testar o envio."
                             : "Nenhum log nessa categoria.")
                            .foregroundColor(Color(white: 0.4))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(filteredLines.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(logColor(line))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Divider().opacity(0.15)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .background(Color(hex: "#05050F").ignoresSafeArea())
            .navigationTitle("Diagnóstico")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Fechar") { dismiss() }.foregroundColor(.white)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { log.clear() }) {
                        Label("Limpar", systemImage: "trash")
                            .foregroundColor(Color(hex: "#FF4444"))
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func logColor(_ line: String) -> Color {
        if line.contains("ERRO") || line.contains("FALHOU") || line.contains("ABORTADO")
            || line.contains("API 4") || line.contains("API 5") {
            return Color(hex: "#FF5555")
        } else if line.contains("ENVIADO") || line.contains("RETRY OK") || line.contains("sucesso") {
            return Color(hex: "#55FF55")
        } else if line.contains("RECEBER") && line.contains("PROCESSANDO") {
            return Color(hex: "#FFAA00")
        } else if line.contains("GPS") || line.contains("localiz") {
            return Color(hex: "#55AAFF")
        } else if line.contains("IGNORADO") {
            return Color(white: 0.4)
        }
        return Color(white: 0.75)
    }
}
