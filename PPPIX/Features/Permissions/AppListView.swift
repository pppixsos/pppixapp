import SwiftUI
import FamilyControls
import ManagedSettings

struct AppListView: View {

    @StateObject private var screenTime = ScreenTimeManager.shared
    @State private var showPicker = false
    @State private var activitySelection = FamilyActivitySelection()
    @State private var isAuthorizing = false
    @State private var errorMessage = ""
    @State private var showPrivacyDisclosure = false
    @State private var savedSelection = false

    var body: some View {
        ZStack {
            Color(hex: "#0A0A12").ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {

                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "apps.iphone.badge.plus")
                            .font(.system(size: 44))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(hex: "#6633FF"), Color(hex: "#3366FF")],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                        Text("Apps Protegidos")
                            .font(.title2.bold())
                            .foregroundColor(.white)
                        Text("Selecione os apps que serão protegidos com senha")
                            .font(.subheadline)
                            .foregroundColor(Color(white: 0.5))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)

                    // Como funciona
                    HowItWorksCard()

                    // Status Screen Time
                    ScreenTimeStatusCard(
                        isAuthorized: screenTime.isAuthorized,
                        isAuthorizing: isAuthorizing
                    ) {
                        Task { await requestAuthorization() }
                    }

                    if screenTime.isAuthorized {
                        // Botão selecionar apps
                        PPPIXButton(title: "Selecionar Apps para Proteger") {
                            showPrivacyDisclosure = true
                        }

                        if savedSelection {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.shield.fill")
                                    .foregroundColor(Color(hex: "#44FF88"))
                                Text("Proteção ativa! Os apps selecionados estão protegidos com senha.")
                                    .font(.footnote)
                                    .foregroundColor(Color(hex: "#44FF88"))
                            }
                            .padding(12)
                            .background(Color(hex: "#44FF88").opacity(0.1))
                            .cornerRadius(10)
                        }

                        // Remover bloqueios
                        PPPIXButton(title: "Remover Todos os Bloqueios", style: .destructive) {
                            screenTime.unblockAll()
                            savedSelection = false
                            activitySelection = FamilyActivitySelection()
                        }
                    }

                    if !errorMessage.isEmpty {
                        ErrorBanner(message: errorMessage)
                    }

                    // Nota sobre iOS
                    iOSNoteCard()

                    Spacer(minLength: 32)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
        }
        .navigationTitle("Apps Protegidos")
        .navigationBarTitleDisplayMode(.inline)
        .familyActivityPicker(isPresented: $showPicker, selection: $activitySelection)
        .onChange(of: activitySelection) { _, newSelection in
            screenTime.blockApps(newSelection)
            savedSelection = true
        }
        .alert("Declaração de Privacidade", isPresented: $showPrivacyDisclosure) {
            Button("Entendi e Aceito") { showPicker = true }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("O PPPIX usa o Screen Time do iOS EXCLUSIVAMENTE para bloquear os apps que você mesmo selecionar. O app não lê, monitora ou transmite o conteúdo de outros aplicativos. Seus dados nunca são vendidos ou compartilhados.")
        }
        .task {
            checkAuthorizationStatus()
        }
    }

    private func checkAuthorizationStatus() {
        let status = AuthorizationCenter.shared.authorizationStatus
        screenTime.isAuthorized = (status == .approved)
    }

    private func requestAuthorization() async {
        isAuthorizing = true
        await screenTime.requestAuthorization()
        isAuthorizing = false
        if !screenTime.isAuthorized {
            errorMessage = "Permissão negada. Vá em Ajustes > Tempo de Uso para conceder."
        }
    }
}

// MARK: - Sub-views

private struct HowItWorksCard: View {
    var body: some View {
        PPPIXCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Como funciona", systemImage: "info.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(hex: "#3366FF"))

                VStack(alignment: .leading, spacing: 8) {
                    HowItWorksStep(number: "1", text: "Você seleciona os apps financeiros que deseja proteger")
                    HowItWorksStep(number: "2", text: "Ao tentar abrir o app, o iOS exibe uma tela de bloqueio")
                    HowItWorksStep(number: "3", text: "O app só abre após digitar a senha correta no PPPIX")
                }
            }
        }
    }
}

private struct HowItWorksStep: View {
    let number: String
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.caption.bold())
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Color(hex: "#3366FF"))
                .clipShape(Circle())
            Text(text)
                .font(.caption)
                .foregroundColor(Color(white: 0.7))
        }
    }
}

private struct ScreenTimeStatusCard: View {
    let isAuthorized: Bool
    let isAuthorizing: Bool
    let onRequest: () -> Void

    var body: some View {
        PPPIXCard {
            HStack(spacing: 14) {
                Image(systemName: isAuthorized ? "checkmark.shield.fill" : "shield.slash.fill")
                    .font(.system(size: 32))
                    .foregroundColor(isAuthorized ? Color(hex: "#44FF88") : Color(hex: "#FF6600"))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Screen Time (Tempo de Uso)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    Text(isAuthorized ? "Autorizado ✓ — Pronto para bloquear apps" : "Necessário para bloquear apps")
                        .font(.caption)
                        .foregroundColor(isAuthorized ? Color(hex: "#44FF88") : Color(white: 0.5))
                }
                Spacer()

                if !isAuthorized {
                    Button {
                        onRequest()
                    } label: {
                        if isAuthorizing {
                            ProgressView().tint(.white).scaleEffect(0.8)
                        } else {
                            Text("Autorizar")
                                .font(.caption.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color(hex: "#3366FF"))
                                .cornerRadius(8)
                        }
                    }
                }
            }
        }
    }
}

private struct iOSNoteCard: View {
    var body: some View {
        PPPIXCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("Diferença do Android", systemImage: "apple.logo")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(white: 0.7))
                Text("No iOS, o bloqueio usa o Screen Time da Apple (mesmo sistema do controle parental). Quando você tenta abrir um app protegido, o iOS exibe uma tela com opção de abrir o PPPIX para digitar a senha.")
                    .font(.caption)
                    .foregroundColor(Color(white: 0.5))
            }
        }
    }
}
