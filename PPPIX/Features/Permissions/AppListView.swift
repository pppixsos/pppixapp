import SwiftUI

struct AppListView: View {

    @State private var errorMessage = ""
    @State private var savedSelection = false
    @State private var isAuthorizing = false

    var body: some View {
        ZStack {
            Color(hex: "#0A0A12").ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {

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

                    #if targetEnvironment(simulator)
                    PPPIXCard {
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(Color(hex: "#FF9900"))
                                .font(.system(size: 32))
                            Text("Simulador detectado")
                                .font(.headline)
                                .foregroundColor(.white)
                            Text("O Screen Time só funciona em iPhone físico.")
                                .font(.caption)
                                .foregroundColor(Color(white: 0.6))
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, 8)
                    }
                    #else
                    ScreenTimeSection(
                        isAuthorizing: $isAuthorizing,
                        savedSelection: $savedSelection,
                        errorMessage: $errorMessage
                    )
                    #endif

                    iOSNoteCard()

                    Spacer(minLength: 32)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
        }
        .navigationTitle("Apps Protegidos")
        .navigationBarTitleDisplayMode(.inline)
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

private struct iOSNoteCard: View {
    var body: some View {
        PPPIXCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("Diferença do Android", systemImage: "apple.logo")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(white: 0.7))
                Text("No iOS, o bloqueio usa o Screen Time da Apple. Quando você tenta abrir um app protegido, o iOS exibe uma tela com opção de abrir o PPPIX para digitar a senha.")
                    .font(.caption)
                    .foregroundColor(Color(white: 0.5))
            }
        }
    }
}

#if !targetEnvironment(simulator)
import FamilyControls
import ManagedSettings

private struct ScreenTimeSection: View {
    @Binding var isAuthorizing: Bool
    @Binding var savedSelection: Bool
    @Binding var errorMessage: String

    @StateObject private var screenTime = ScreenTimeManager.shared
    @State private var activitySelection = FamilyActivitySelection()
    @State private var showPicker = false  // binding dedicado ao picker

    var body: some View {
        VStack(spacing: 12) {
            PPPIXCard {
                HStack(spacing: 14) {
                    Image(systemName: screenTime.isAuthorized ? "checkmark.shield.fill" : "shield.slash.fill")
                        .font(.system(size: 32))
                        .foregroundColor(screenTime.isAuthorized ? Color(hex: "#44FF88") : Color(hex: "#FF6600"))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Screen Time")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                        Text(screenTime.isAuthorized ? "Autorizado ✓" : "Necessário para bloquear apps")
                            .font(.caption)
                            .foregroundColor(screenTime.isAuthorized ? Color(hex: "#44FF88") : Color(white: 0.5))
                    }
                    Spacer()

                    if !screenTime.isAuthorized {
                        Button {
                            Task { await requestAuth() }
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

            if screenTime.isAuthorized {
                PPPIXButton(title: "Selecionar Apps para Proteger") {
                    showPicker = true  // abre APENAS o picker
                }

                if savedSelection {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundColor(Color(hex: "#44FF88"))
                        Text("Proteção ativa!")
                            .font(.footnote)
                            .foregroundColor(Color(hex: "#44FF88"))
                    }
                    .padding(12)
                    .background(Color(hex: "#44FF88").opacity(0.1))
                    .cornerRadius(10)
                }

                PPPIXButton(title: "Remover Todos os Bloqueios", style: .destructive) {
                    screenTime.unblockAll()
                    savedSelection = false
                }
            }

            if !errorMessage.isEmpty {
                ErrorBanner(message: errorMessage)
            }
        }
        .familyActivityPicker(isPresented: $showPicker, selection: $activitySelection)
        .onChange(of: activitySelection) { newSelection in
            screenTime.blockApps(newSelection)
            savedSelection = true
        }
        .task {
            screenTime.isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
        }
    }

    private func requestAuth() async {
        isAuthorizing = true
        await screenTime.requestAuthorization()
        isAuthorizing = false
        if !screenTime.isAuthorized {
            errorMessage = "Permissão negada. Vá em Ajustes > Tempo de Uso."
        }
    }
}
#endif
