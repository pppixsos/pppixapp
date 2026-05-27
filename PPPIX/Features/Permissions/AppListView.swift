import SwiftUI

#if !targetEnvironment(simulator)
import FamilyControls

struct AppListView: View {
    @StateObject private var manager = ScreenTimeManager.shared
    @State private var showPicker = false
    @State private var tempSelection = FamilyActivitySelection()
    @State private var showConfirm = false
    @State private var showRemoveConfirm = false

    var body: some View {
        ZStack {
            Color(hex: "#0A0A12").ignoresSafeArea()

            if !manager.isAuthorized {
                // Ainda não tem permissão Screen Time
                VStack(spacing: 20) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(LinearGradient(
                            colors: [Color(hex: "#3366FF"), Color(hex: "#6633FF")],
                            startPoint: .top, endPoint: .bottom
                        ))

                    Text("Permissão Necessária")
                        .font(.title2.bold())
                        .foregroundColor(.white)

                    Text("Para bloquear apps, o PPPIX precisa de acesso ao Screen Time do iOS.")
                        .font(.subheadline)
                        .foregroundColor(Color(white: 0.5))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    Button {
                        Task { await manager.requestAuthorization() }
                    } label: {
                        Text("Conceder Acesso")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity).frame(height: 52)
                            .background(Color(hex: "#3366FF"))
                            .cornerRadius(13)
                            .padding(.horizontal, 32)
                    }
                }
            } else {
                // Tem permissão — mostrar seleção atual
                ScrollView {
                    VStack(spacing: 20) {

                        // Card de status
                        VStack(spacing: 12) {
                            HStack {
                                Image(systemName: manager.hasBlockedApps ? "lock.shield.fill" : "shield")
                                    .font(.system(size: 28))
                                    .foregroundColor(manager.hasBlockedApps ? Color(hex: "#44FF88") : Color(white: 0.4))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(manager.hasBlockedApps ? "Proteção Ativa" : "Nenhum App Protegido")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.white)
                                    Text(manager.hasBlockedApps
                                         ? "Apps bloqueados exigem senha para abrir"
                                         : "Toque em 'Escolher Apps' para proteger")
                                        .font(.caption)
                                        .foregroundColor(Color(white: 0.5))
                                }
                                Spacer()
                            }
                        }
                        .padding(16)
                        .background(Color(hex: "#141422"))
                        .cornerRadius(14)

                        // Botão principal — abre o FamilyActivityPicker nativo do iOS
                        // Este picker mostra TODOS os apps instalados com ícone real
                        Button {
                            tempSelection = manager.currentSelection
                            showPicker = true
                        } label: {
                            HStack {
                                Image(systemName: "apps.iphone")
                                    .font(.system(size: 18))
                                Text(manager.hasBlockedApps ? "Alterar Apps Protegidos" : "Escolher Apps para Proteger")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity).frame(height: 52)
                            .background(LinearGradient(
                                colors: [Color(hex: "#3366FF"), Color(hex: "#6633FF")],
                                startPoint: .leading, endPoint: .trailing
                            ))
                            .cornerRadius(13)
                        }

                        if manager.hasBlockedApps {
                            // Info sobre como funciona
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Como funciona")
                                    .font(.caption.bold())
                                    .foregroundColor(Color(white: 0.4))
                                    .padding(.horizontal, 4)

                                InfoRow(icon: "1.circle.fill", color: "#3366FF",
                                        text: "Ao tentar abrir um app protegido, o iOS mostra a tela do PPPIX")
                                InfoRow(icon: "2.circle.fill", color: "#3366FF",
                                        text: "Toque em 'Digitar Senha' e o PPPIX abre")
                                InfoRow(icon: "3.circle.fill", color: "#3366FF",
                                        text: "Senha normal: abre o app. Senha de emergência: abre + envia alerta")
                            }
                            .padding(16)
                            .background(Color(hex: "#141422"))
                            .cornerRadius(14)

                            // Botão remover proteção
                            Button {
                                showRemoveConfirm = true
                            } label: {
                                HStack {
                                    Image(systemName: "lock.open")
                                    Text("Remover Toda Proteção")
                                }
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Color(hex: "#FF4444"))
                                .frame(maxWidth: .infinity).frame(height: 44)
                                .background(Color(hex: "#FF4444").opacity(0.1))
                                .cornerRadius(10)
                                .overlay(RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color(hex: "#FF4444").opacity(0.3), lineWidth: 1))
                            }
                        }

                        Spacer(minLength: 32)
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle("Apps Protegidos")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { manager.checkAuthorization() }
        // FamilyActivityPicker — picker nativo do iOS com todos os apps instalados + ícones reais
        .familyActivityPicker(isPresented: $showPicker, selection: $tempSelection)
        .onChange(of: showPicker) { isOpen in
            // Quando picker fecha, confirmar seleção
            if !isOpen && (tempSelection.applicationTokens != manager.currentSelection.applicationTokens
                           || tempSelection.categoryTokens != manager.currentSelection.categoryTokens) {
                showConfirm = true
            }
        }
        .confirmationDialog("Ativar proteção?", isPresented: $showConfirm, titleVisibility: .visible) {
            Button("Ativar Proteção") {
                manager.applySelection(tempSelection)
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Os apps selecionados pedirão senha ao serem abertos.")
        }
        .confirmationDialog("Remover proteção?", isPresented: $showRemoveConfirm, titleVisibility: .visible) {
            Button("Remover", role: .destructive) {
                manager.unblockAll()
                manager.currentSelection = FamilyActivitySelection()
                if let defaults = UserDefaults(suiteName: "group.tech.pppix.app") {
                    defaults.removeObject(forKey: ScreenTimeManager.selectionKey)
                }
            }
            Button("Cancelar", role: .cancel) {}
        }
    }
}

private struct InfoRow: View {
    let icon: String
    let color: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(Color(hex: color))
                .font(.system(size: 16))
            Text(text)
                .font(.caption)
                .foregroundColor(Color(white: 0.6))
            Spacer()
        }
    }
}

#else

// Stub para Simulator
struct AppListView: View {
    var body: some View {
        ZStack {
            Color(hex: "#0A0A12").ignoresSafeArea()
            Text("Screen Time não disponível no Simulator")
                .foregroundColor(.white)
        }
        .navigationTitle("Apps Protegidos")
    }
}

#endif
