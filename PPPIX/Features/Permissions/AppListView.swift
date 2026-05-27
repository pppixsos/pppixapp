import SwiftUI

struct AppListView: View {

    @StateObject private var manager = AppBlockManager.shared
    @State private var searchText = ""
    @State private var selectedApp: InstalledApp?
    @State private var showBlockingFlow = false
    @State private var appToUnblock: InstalledApp?
    @State private var showUnblockConfirm = false

    var filteredApps: [InstalledApp] {
        guard !searchText.isEmpty else { return manager.installedApps }
        return manager.installedApps.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.id.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        ZStack {
            Color(hex: "#0A0A12").ignoresSafeArea()

            VStack(spacing: 0) {

                // Apps protegidos ativos
                if !manager.blockedApps.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PROTEGIDOS")
                            .font(.caption.bold())
                            .foregroundColor(Color(hex: "#44FF88"))
                            .padding(.horizontal, 20)
                            .padding(.top, 12)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(manager.blockedApps) { app in
                                    BlockedChip(app: app) {
                                        appToUnblock = app
                                        showUnblockConfirm = true
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 10)
                        }
                        Divider().background(Color(white: 0.1))
                    }
                }

                // Busca
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(Color(white: 0.4))
                        .font(.system(size: 14))
                    TextField("Buscar app...", text: $searchText)
                        .foregroundColor(.white)
                        .autocorrectionDisabled()
                        .font(.system(size: 15))
                }
                .padding(10)
                .background(Color(white: 0.07))
                .cornerRadius(10)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                // Conteúdo principal
                if manager.isLoadingApps {
                    Spacer()
                    VStack(spacing: 14) {
                        ProgressView()
                            .tint(Color(hex: "#3366FF"))
                            .scaleEffect(1.4)
                        Text("Carregando apps instalados...")
                            .font(.subheadline)
                            .foregroundColor(Color(white: 0.5))
                    }
                    Spacer()
                } else if manager.installedApps.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "tray.fill")
                            .font(.system(size: 40))
                            .foregroundColor(Color(white: 0.2))
                        Text("Nenhum app encontrado")
                            .foregroundColor(Color(white: 0.4))
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredApps) { app in
                                AppRow(
                                    app: app,
                                    isBlocked: manager.blockedApps.contains { $0.id == app.id }
                                ) {
                                    if manager.blockedApps.contains(where: { $0.id == app.id }) {
                                        appToUnblock = app
                                        showUnblockConfirm = true
                                    } else {
                                        selectedApp = app
                                        showBlockingFlow = true
                                    }
                                }
                                Divider().background(Color(white: 0.07)).padding(.leading, 72)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Apps Protegidos")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { manager.loadInstalledApps() }
        .sheet(isPresented: $showBlockingFlow) {
            if let app = selectedApp {
                BlockingSetupSheet(app: app, isPresented: $showBlockingFlow)
            }
        }
        .confirmationDialog(
            "Desproteger \(appToUnblock?.name ?? "")?",
            isPresented: $showUnblockConfirm,
            titleVisibility: .visible
        ) {
            Button("Desproteger", role: .destructive) {
                if let app = appToUnblock { manager.unblockApp(app) }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("O app original voltará para a tela inicial. Remova também o perfil em Configurações > Geral > VPN e Gerenciamento.")
        }
    }
}

// MARK: — AppRow
private struct AppRow: View {
    let app: InstalledApp
    let isBlocked: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                AppIconView(iconData: app.iconData, size: 46)

                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(app.id)
                        .font(.system(size: 11))
                        .foregroundColor(Color(white: 0.3))
                        .lineLimit(1)
                }

                Spacer()

                if isBlocked {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10))
                        Text("Protegido")
                            .font(.caption.bold())
                    }
                    .foregroundColor(Color(hex: "#44FF88"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(hex: "#44FF88").opacity(0.1))
                    .cornerRadius(8)
                } else {
                    Image(systemName: "shield.badge.plus")
                        .foregroundColor(Color(hex: "#3366FF"))
                        .font(.system(size: 18))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: — Chip de app bloqueado
private struct BlockedChip: View {
    let app: InstalledApp
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            AppIconView(iconData: app.iconData, size: 26)
            Text(app.name)
                .font(.caption.bold())
                .foregroundColor(.white)
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(Color(white: 0.45))
                    .font(.system(size: 13))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(white: 0.09))
        .cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20)
            .stroke(Color(hex: "#44FF88").opacity(0.25), lineWidth: 1))
    }
}

// MARK: — Ícone do app (reutilizável)
struct AppIconView: View {
    let iconData: Data?
    let size: CGFloat

    var body: some View {
        Group {
            if let data = iconData, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(Color(white: 0.35))
                    .padding(10)
                    .background(Color(white: 0.13))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
    }
}

// MARK: — Sheet de ativação da proteção
struct BlockingSetupSheet: View {
    let app: InstalledApp
    @Binding var isPresented: Bool
    @StateObject private var manager = AppBlockManager.shared
    @State private var step = 0  // 0 = explicação, 1 = aguardando instalação
    @State private var isInstalling = false
    @State private var errorMsg = ""

    var body: some View {
        NavigationView {
            ZStack {
                Color(hex: "#0A0A12").ignoresSafeArea()

                VStack(spacing: 28) {
                    // Ícone do app
                    AppIconView(iconData: app.iconData, size: 76)
                        .padding(.top, 8)

                    Text(step == 0 ? "Proteger \(app.name)" : "Instale o Perfil")
                        .font(.title3.bold())
                        .foregroundColor(.white)

                    if step == 0 {
                        // Explicação do que vai acontecer
                        VStack(spacing: 14) {
                            StepInfo(icon: "eye.slash.fill", color: "#FF6644",
                                     title: "App original é ocultado",
                                     desc: "O \(app.name) original some da tela inicial")
                            StepInfo(icon: "doc.badge.plus", color: "#3366FF",
                                     title: "Atalho idêntico criado",
                                     desc: "Um atalho com o mesmo ícone e nome aparece no lugar")
                            StepInfo(icon: "lock.shield.fill", color: "#44FF88",
                                     title: "Senha obrigatória",
                                     desc: "Ao tocar no atalho, o PPPIX pede senha antes de abrir")
                        }
                        .padding(.horizontal, 8)

                        Spacer()

                        if !errorMsg.isEmpty {
                            Text(errorMsg)
                                .font(.caption)
                                .foregroundColor(Color(hex: "#FF4444"))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }

                        VStack(spacing: 12) {
                            Button {
                                activate()
                            } label: {
                                Group {
                                    if isInstalling {
                                        ProgressView().tint(.white)
                                    } else {
                                        Text("Ativar Proteção")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(.white)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(LinearGradient(
                                    colors: [Color(hex: "#3366FF"), Color(hex: "#6633FF")],
                                    startPoint: .leading, endPoint: .trailing))
                                .cornerRadius(13)
                            }
                            .disabled(isInstalling)
                            .padding(.horizontal, 24)

                            Button("Cancelar") { isPresented = false }
                                .font(.subheadline)
                                .foregroundColor(Color(white: 0.4))
                        }
                        .padding(.bottom, 24)

                    } else {
                        // Instruções para instalar o perfil
                        VStack(spacing: 16) {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.system(size: 60))
                                .foregroundColor(Color(hex: "#44FF88"))

                            Text("O Safari abriu com o perfil de segurança.\n\nSiga os passos:")
                                .font(.subheadline)
                                .foregroundColor(Color(white: 0.6))
                                .multilineTextAlignment(.center)

                            VStack(alignment: .leading, spacing: 10) {
                                InstructionLine(n: "1", text: "Toque em \"Permitir\" no Safari")
                                InstructionLine(n: "2", text: "Abra Configurações → Geral → VPN e Gerenciamento")
                                InstructionLine(n: "3", text: "Toque em \"PPPIX – \(app.name)\" → Instalar")
                                InstructionLine(n: "4", text: "Volte ao PPPIX e toque em Concluído")
                            }
                            .padding(.horizontal, 24)
                        }

                        Spacer()

                        Button("Concluído") { isPresented = false }
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color(hex: "#44FF88"))
                            .cornerRadius(13)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 24)
                    }
                }
                .padding(.horizontal, 16)
            }
            .navigationBarHidden(true)
        }
    }

    private func activate() {
        isInstalling = true
        errorMsg = ""
        manager.blockApp(app) { success in
            isInstalling = false
            if success {
                step = 1
            } else {
                errorMsg = "Não foi possível abrir o Safari. Tente novamente."
            }
        }
    }
}

private struct StepInfo: View {
    let icon: String; let color: String
    let title: String; let desc: String
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(Color(hex: color))
                .frame(width: 38, height: 38)
                .background(Color(hex: color).opacity(0.1))
                .cornerRadius(10)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                Text(desc).font(.caption).foregroundColor(Color(white: 0.5))
            }
            Spacer()
        }
    }
}

private struct InstructionLine: View {
    let n: String; let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(n)
                .font(.caption.bold()).foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Color(hex: "#3366FF")).clipShape(Circle())
            Text(text).font(.subheadline).foregroundColor(Color(white: 0.7))
            Spacer()
        }
    }
}
