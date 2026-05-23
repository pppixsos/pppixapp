import SwiftUI

/// Equivalente ao LockScreenActivity.kt do Android.
/// No iOS é apresentado como tela de desbloqueio quando o usuário abre o PPPIX
/// após tentar abrir um app bloqueado pelo Screen Time.
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
            // Dark background
            Color(hex: "#05050F").ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // Lock icon
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

                    Text(""\(appName)" está bloqueado")
                        .font(.title3.bold())
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)

                    Text("Digite sua senha para continuar")
                        .font(.subheadline)
                        .foregroundColor(Color(white: 0.5))
                }

                // Password field
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

                // Footer
                Text("PPPIX • Segurança Financeira")
                    .font(.caption2)
                    .foregroundColor(Color(white: 0.2))
                    .padding(.bottom, 20)
            }
        }
        .interactiveDismissDisabled() // Não permite fechar por swipe
    }

    // MARK: - Verify

    private func verifyPassword() async {
        guard !password.isEmpty else {
            errorMessage = "Digite a senha."
            return
        }

        isLoading = true
        errorMessage = ""

        // Pega localização
        let coord = await LocationService.shared.getCurrentLocation()

        do {
            let resp = try await APIClient.shared.verifyPassword(body: VerifyPasswordRequest(
                password: password,
                latitude: coord?.latitude,
                longitude: coord?.longitude
            ))

            switch resp.action {
            case "open_bank":
                // Senha correta — desbloqueia normalmente
                onUnlocked?()
                dismiss()

            case "open_ppix":
                // Abre configurações do PPPIX
                onUnlocked?()
                dismiss()
                NotificationCenter.default.post(name: .openPPPIXSettings, object: nil)

            case "open_bank_alert":
                // Senha de emergência — desbloqueia + envia alerta silencioso
                onUnlocked?()
                sendSilentAlert(coord: coord)
                dismiss()

            default:
                if resp.limitExceeded {
                    // Backend já enviou alerta por excesso de tentativas
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

    // MARK: - Silent Alert (idêntico ao sendSilentAlert do Android)

    private func sendSilentAlert(coord: CLLocationCoordinate2D?) {
        let myEmail = SessionManager.shared.userEmail
        let userName = SessionManager.shared.userName

        Task {
            do {
                // 1. Contatos aceitos
                let connections = (try? await APIClient.shared.getAcceptedConnections()) ?? []
                let recipientIds = connections.map { $0.userId(myEmail: myEmail) }.filter { $0 > 0 }

                // 2. Veículo ativo
                let vehicles = (try? await APIClient.shared.getVehicles()) ?? []
                let vehicle = vehicles.first(where: { $0.is_active }) ?? vehicles.first
                let vehiclePayload = vehicle.map {
                    VehicleInfoPayload(
                        model: $0.model,
                        license_plate: $0.license_plate,
                        color: $0.color,
                        year: $0.year
                    )
                }

                // 3. Monta e envia
                let body = SendAlertRequest(
                    alert_type: "emergency_password",
                    priority: "critical",
                    title: "🚨 Senha de Emergência",
                    message: "\(userName) utilizou a senha de emergência e pode estar em perigo!",
                    latitude: coord.map { String(format: "%.6f", $0.latitude) },
                    longitude: coord.map { String(format: "%.6f", $0.longitude) },
                    metadata: AlertMetadata(
                        timestamp: String(Int(Date().timeIntervalSince1970 * 1000)),
                        vehicle_info: vehiclePayload
                    ),
                    recipient_ids: recipientIds
                )

                _ = try await APIClient.shared.sendAlert(body: body)
            } catch {
                // Alerta silencioso — falha silenciosa
            }
        }
    }
}

import CoreLocation

extension Notification.Name {
    static let openPPPIXSettings = Notification.Name("pppix.openSettings")
}
