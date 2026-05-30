import SwiftUI
import CoreLocation

struct LockScreenView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var showPassword = false
    @State private var isLoading = false
    @State private var errorMessage = ""

    var appName: String = "Aplicativo"
    var onUnlocked: (() -> Void)? = nil

    var body: some View {
        ZStack {
            Color(hex: "#05050F").ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                VStack(spacing: 16) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "#3366FF"), Color(hex: "#6633FF")],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    Text("\(appName) esta bloqueado")
                        .font(.title3.bold())
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)

                    Text("Digite sua senha para continuar")
                        .font(.subheadline)
                        .foregroundColor(Color(white: 0.5))
                }

                VStack(spacing: 16) {
                    PPPIXSecureField(
                        title: "Senha",
                        placeholder: "Digite sua senha",
                        text: $password,
                        showPassword: $showPassword
                    )
                    .padding(.horizontal, 32)

                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundColor(Color(hex: "#FF4444"))
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        Task { await verifyPassword() }
                    } label: {
                        Group {
                            if isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Text("Desbloquear")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: "#3366FF"), Color(hex: "#6633FF")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(12)
                    }
                    .disabled(isLoading)
                    .padding(.horizontal, 32)
                }

                Spacer()

                Text("PPPIX • Segurança Financeira")
                    .font(.caption2)
                    .foregroundColor(Color(white: 0.2))
                    .padding(.bottom, 20)
            }
        }
        .interactiveDismissDisabled()
    }

    private func verifyPassword() async {
        guard !password.isEmpty else {
            errorMessage = "Digite a senha."
            return
        }

        isLoading = true
        errorMessage = ""

        let coord = await LocationService.shared.getCurrentLocation()

        do {
            let resp = try await APIClient.shared.verifyPassword(body: VerifyPasswordRequest(
                password: password,
                latitude: coord?.latitude,
                longitude: coord?.longitude
            ))

            switch resp.action {
            case "open_bank":
                onUnlocked?()
                dismiss()

            case "open_pppix", "open_ppix":
                onUnlocked?()
                dismiss()
                NotificationCenter.default.post(name: .openPPPIXSettings, object: nil)

            case "open_bank_alert":
                // Envia o alerta ANTES de fechar a tela
                // Importante: não chamar dismiss() antes para o Task não ser cancelado
                sendSilentAlert(coord: coord)
                onUnlocked?()
                dismiss()

            default:
                if resp.limitExceeded {
                    onUnlocked?()
                    dismiss()
                } else {
                    errorMessage = "Senha incorreta."
                    password = ""
                }
            }
        } catch APIError.unauthorized {
            errorMessage = "Sessão expirada. Abra o PPPIX e faça login."
        } catch {
            errorMessage = "Sem conexão. Verifique sua internet."
        }

        isLoading = false
    }

    private func sendSilentAlert(coord: CLLocationCoordinate2D?) {
        let myEmail  = SessionManager.shared.userEmail
        let userName = SessionManager.shared.userName
        let latStr   = coord.map { String(format: "%.6f", $0.latitude) }
        let lonStr   = coord.map { String(format: "%.6f", $0.longitude) }

        print("[PPPIX] sendSilentAlert início — user=\(myEmail) lat=\(latStr ?? "nil")")
        Task { @MainActor in AlertDiagnosticLog.shared.log("[PPPIX] sendSilentAlert início — user=\(myEmail) lat=\(latStr ?? "nil")") }

        guard !myEmail.isEmpty else {
            print("[PPPIX] sendSilentAlert ABORTADO — userEmail vazio")
            Task { @MainActor in AlertDiagnosticLog.shared.log("[PPPIX] sendSilentAlert ABORTADO — userEmail vazio") }
            return
        }

        // Task.detached: não é cancelado quando a View é destruída pelo dismiss()
        // @MainActor para acessar APIClient (que é @MainActor)
        Task { @MainActor in
            do {
                // 1. Buscar conexões aceitas para obter recipient_ids
                let connections = (try? await APIClient.shared.getAcceptedConnections()) ?? []
                let recipientIds = connections.map { $0.userId(myEmail: myEmail) }.filter { $0 > 0 }
                print("[PPPIX] sendSilentAlert — \(connections.count) conexões, ids: \(recipientIds)")
                Task { @MainActor in AlertDiagnosticLog.shared.log("[PPPIX] sendSilentAlert — \(connections.count) conexões, ids: \(recipientIds)") }

                // 2. Veículo ativo
                let vehicles = (try? await APIClient.shared.getVehicles()) ?? []
                let vehicle = vehicles.first(where: { $0.is_active }) ?? vehicles.first
                let vehiclePayload = vehicle.map {
                    VehicleInfoPayload(model: $0.model, license_plate: $0.license_plate,
                                       color: $0.color, year: $0.year)
                }

                // 3. Enviar alerta
                let body = SendAlertRequest(
                    alert_type: "emergency_password",
                    priority: "critical",
                    title: "🚨 Senha de Emergência",
                    message: "\(userName) utilizou a senha de emergência e pode estar em perigo!",
                    latitude: latStr,
                    longitude: lonStr,
                    metadata: AlertMetadata(
                        timestamp: String(Int(Date().timeIntervalSince1970 * 1000)),
                        vehicle_info: vehiclePayload
                    ),
                    recipient_ids: recipientIds
                )
                // Log do payload para debug
                if let jsonData = try? JSONEncoder().encode(body),
                   let jsonStr = String(data: jsonData, encoding: .utf8) {
                    print("[PPPIX] sendSilentAlert payload: \(jsonStr)")
                    Task { @MainActor in AlertDiagnosticLog.shared.log("[PPPIX] sendSilentAlert payload: \(jsonStr)") }
                }
                let result = try await APIClient.shared.sendAlert(body: body)
                print("[PPPIX] sendSilentAlert ENVIADO — id=\(result.id)")
                Task { @MainActor in AlertDiagnosticLog.shared.log("[PPPIX] sendSilentAlert ENVIADO — id=\(result.id)") }
            } catch APIError.forbidden(let msg) {
                // 403: assinatura necessária — logar claramente
                print("[PPPIX] sendSilentAlert BLOQUEADO (assinatura): \(msg)")
                AlertDiagnosticLog.shared.log("ENVIAR ERRO 403: \(msg)")
            } catch {
                // Outro erro: retry sem recipient_ids
                print("[PPPIX] sendSilentAlert ERRO: \(error) — tentando retry")
                AlertDiagnosticLog.shared.log("ENVIAR ERRO: \(error) — retry sem ids")
                do {
                    let body = SendAlertRequest(
                        alert_type: "emergency_password",
                        priority: "critical",
                        title: "🚨 Senha de Emergência",
                        message: "\(userName) utilizou a senha de emergência e pode estar em perigo!",
                        latitude: latStr,
                        longitude: lonStr,
                        metadata: AlertMetadata(
                            timestamp: String(Int(Date().timeIntervalSince1970 * 1000)),
                            vehicle_info: nil
                        ),
                        recipient_ids: []
                    )
                    let result = try await APIClient.shared.sendAlert(body: body)
                    print("[PPPIX] sendSilentAlert RETRY OK — id=\(result.id)")
                    AlertDiagnosticLog.shared.log("ENVIAR RETRY OK — id=\(result.id)")
                } catch APIError.forbidden(let msg) {
                    AlertDiagnosticLog.shared.log("ENVIAR RETRY ERRO 403: \(msg)")
                } catch {
                    print("[PPPIX] sendSilentAlert RETRY FALHOU: \(error)")
                    AlertDiagnosticLog.shared.log("ENVIAR RETRY FALHOU: \(error)")
                }
            }
        }
    }
}

extension Notification.Name {
    static let openPPPIXSettings = Notification.Name("pppix.openSettings")
}
