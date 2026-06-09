import SwiftUI

#if !targetEnvironment(simulator)
import FamilyControls

struct AppListView: View {
    @ObservedObject private var manager = ScreenTimeManager.shared
    @State private var showPicker = false
    @State private var tempSelection = FamilyActivitySelection()
    @State private var showConfirm = false
    @State private var showRemoveConfirm = false

    var body: some View {
        ZStack {
            Color(hex: "#0A0A12").ignoresSafeArea()

            if !manager.isAuthorized {
                unauthorizedView
            } else {
                authorizedView
            }
        }
        .navigationTitle("Apps Protegidos")
        .navigationBarTitleDisplayMode(.large)
        .onAppear { manager.checkAuthorization() }
        .familyActivityPicker(isPresented: $showPicker, selection: $tempSelection)
        .onChange(of: showPicker) { isOpen in
            if !isOpen {
                let changed = tempSelection.applicationTokens != manager.currentSelection.applicationTokens
                    || tempSelection.categoryTokens != manager.currentSelection.categoryTokens
                if changed && (!tempSelection.applicationTokens.isEmpty || !tempSelection.categoryTokens.isEmpty) {
                    showConfirm = true
                }
            }
        }
        .confirmationDialog("Ativar proteção?", isPresented: $showConfirm, titleVisibility: .visible) {
            Button("Ativar Proteção") {
                manager.applySelection(tempSelection)
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Os apps selecionados exigirão senha ao serem abertos.")
        }
        .confirmationDialog("Remover proteção?", isPresented: $showRemoveConfirm, titleVisibility: .visible) {
            Button("Remover Tudo", role: .destructive) {
                ScreenTimeManager.shared.removeShield()
                ScreenTimeManager.shared.currentSelection = FamilyActivitySelection()
                UserDefaults(suiteName: "group.tech.pppix.app")?
                    .removeObject(forKey: ScreenTimeManager.selectionKey)
            }
            Button("Cancelar", role: .cancel) {}
        }
    }

    // MARK: - Tela sem permissão
    private var unauthorizedView: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                // Ícone
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color(hex: "#3366FF").opacity(0.15), Color(hex: "#6633FF").opacity(0.08)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 96, height: 96)

                    Image(systemName: "lock.shield")
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(LinearGradient(
                            colors: [Color(hex: "#3366FF"), Color(hex: "#6633FF")],
                            startPoint: .top, endPoint: .bottom
                        ))
                }

                VStack(spacing: 8) {
                    Text("Permissão Necessária")
                        .font(.title3.bold())
                        .foregroundColor(.white)

                    Text("O PPPIX precisa de acesso ao Screen Time para proteger seus apps com senha.")
                        .font(.subheadline)
                        .foregroundColor(Color(white: 0.45))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .lineSpacing(3)
                }

                Button {
                    Task { await manager.requestAuthorization() }
                } label: {
                    Text("Continuar")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(LinearGradient(
                            colors: [Color(hex: "#3366FF"), Color(hex: "#6633FF")],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .cornerRadius(14)
                }
                .padding(.horizontal, 28)
                .padding(.top, 8)
            }

            Spacer()
        }
    }

    // MARK: - Tela com permissão
    private var authorizedView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {

                // Card de status
                statusCard

                // Botão principal — abre FamilyActivityPicker
                Button {
                    tempSelection = manager.currentSelection
                    showPicker = true
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(LinearGradient(
                                    colors: [Color(hex: "#3366FF"), Color(hex: "#6633FF")],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ))
                                .frame(width: 34, height: 34)

                            Image(systemName: "apps.iphone")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white)
                        }

                        Text(manager.hasBlockedApps ? "Alterar Apps Protegidos" : "Escolher Apps para Proteger")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color(white: 0.3))
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 60)
                    .background(Color(hex: "#141422"))
                    .cornerRadius(14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color(white: 0.08), lineWidth: 1)
                    )
                }

                if manager.hasBlockedApps {
                    // Como funciona
                    howItWorksCard

                    // Remover proteção
                    Button {
                        showRemoveConfirm = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "lock.open.fill")
                                .font(.system(size: 13))
                            Text("Remover Toda Proteção")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(Color(hex: "#FF4444"))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color(hex: "#FF4444").opacity(0.07))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color(hex: "#FF4444").opacity(0.2), lineWidth: 1)
                        )
                    }
                }

                Spacer(minLength: 40)
            }
            .padding(16)
        }
    }

    // MARK: - Card de status
    private var statusCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(manager.hasBlockedApps
                          ? Color(hex: "#44FF88").opacity(0.12)
                          : Color(white: 0.07))
                    .frame(width: 50, height: 50)

                Image(systemName: manager.hasBlockedApps ? "lock.shield.fill" : "shield")
                    .font(.system(size: 22))
                    .foregroundColor(manager.hasBlockedApps
                                     ? Color(hex: "#44FF88")
                                     : Color(white: 0.3))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(manager.hasBlockedApps ? "Proteção Ativa" : "Sem Proteção")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)

                Text(manager.hasBlockedApps
                     ? "Apps selecionados exigem senha"
                     : "Nenhum app protegido ainda")
                    .font(.caption)
                    .foregroundColor(Color(white: 0.4))
            }

            Spacer()

            if manager.hasBlockedApps {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(hex: "#44FF88"))
                        .frame(width: 6, height: 6)
                    Text("Ativo")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(hex: "#44FF88"))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(hex: "#44FF88").opacity(0.1))
                .cornerRadius(20)
            }
        }
        .padding(16)
        .background(Color(hex: "#141422"))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    manager.hasBlockedApps
                        ? Color(hex: "#44FF88").opacity(0.15)
                        : Color(white: 0.06),
                    lineWidth: 1
                )
        )
    }

    // MARK: - Card como funciona
    private var howItWorksCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Como funciona")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Color(white: 0.3))
                .textCase(.uppercase)
                .tracking(0.8)

            VStack(spacing: 0) {
                StepRow(icon: "1.circle.fill", text: "Abra qualquer app protegido — aparece a tela do PPPIX")
                Divider().background(Color(white: 0.07)).padding(.leading, 36)
                StepRow(icon: "2.circle.fill", text: "Toque em \"Digitar Senha\" — o PPPIX abre com o campo de senha")
                Divider().background(Color(white: 0.07)).padding(.leading, 36)
                StepRow(icon: "3.circle.fill", text: "Senha normal: libera o app por 5 minutos")
                Divider().background(Color(white: 0.07)).padding(.leading, 36)
                StepRow(icon: "4.circle.fill", text: "Senha de emergência: libera + envia alerta ao grupo")
            }
        }
        .padding(16)
        .background(Color(hex: "#141422"))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(white: 0.06), lineWidth: 1)
        )
    }
}

// MARK: - Componentes
private struct StepRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(Color(hex: "#3366FF"))
                .frame(width: 24)

            Text(text)
                .font(.system(size: 13))
                .foregroundColor(Color(white: 0.55))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(.vertical, 10)
    }
}

#else

struct AppListView: View {
    var body: some View {
        ZStack {
            Color(hex: "#0A0A12").ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 48))
                    .foregroundColor(Color(hex: "#3366FF"))
                Text("Screen Time não disponível no Simulator")
                    .foregroundColor(Color(white: 0.5))
                    .multilineTextAlignment(.center)
            }
            .padding(32)
        }
        .navigationTitle("Apps Protegidos")
    }
}

#endif
