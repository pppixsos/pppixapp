import SwiftUI

struct ProfileView: View {

    @ObservedObject private var session = SessionManager.shared
    @State private var isLoadingFresh = false
    @State private var showLogoutConfirm = false
    @State private var showDiagnostic = false
    @State private var showDeleteAccountConfirm = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountError = ""

    var body: some View {
        ZStack {
            Color(hex: "#0A0A12").ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {

                    // Avatar + nome
                    VStack(spacing: 12) {
                        Text(String(session.userName.prefix(1)).uppercased())
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 80, height: 80)
                            .background(
                                LinearGradient(
                                    colors: [Color(hex: "#3366FF"), Color(hex: "#6633FF")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .clipShape(Circle())

                        Text(session.userName)
                            .font(.title3.bold())
                            .foregroundColor(.white)
                        Text(session.userEmail)
                            .font(.subheadline)
                            .foregroundColor(Color(white: 0.5))
                    }
                    .padding(.top, 16)

                    // Info card
                    PPPIXCard {
                        VStack(spacing: 0) {
                            ProfileInfoRow(label: "Nome", value: session.userName)
                            Divider().overlay(Color(white: 0.1))
                            ProfileInfoRow(label: "Email", value: session.userEmail)
                            Divider().overlay(Color(white: 0.1))
                            ProfileInfoRow(label: "ID", value: "\(session.userId)")
                        }
                    }

                    // Disfarce do app
                    NavigationLink {
                        AppDisguiseView()
                    } label: {
                        HStack {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(white: 0.1))
                                    .frame(width: 32, height: 32)
                                Image(systemName: "theatermasks.fill")
                                    .foregroundColor(Color(hex: "#3366FF"))
                                    .font(.system(size: 14))
                            }
                            Text("Disfarçar o App")
                                .font(.subheadline)
                                .foregroundColor(.white)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(Color(white: 0.3))
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(Color(white: 0.05))
                        .cornerRadius(10)
                    }

                    // Links
                    PPPIXCard {
                        VStack(spacing: 0) {
                            ProfileLinkRow(
                                icon: "doc.text.fill",
                                title: "Política de Privacidade",
                                url: "https://privacidade.pppix.online/ios"
                            )
                        }
                    }

                    // Excluir conta
                    Button {
                        showDeleteAccountConfirm = true
                    } label: {
                        HStack {
                            Image(systemName: "trash.fill")
                                .foregroundColor(Color(hex: "#FF4444"))
                                .font(.system(size: 14))
                            Text("Excluir Minha Conta")
                                .font(.subheadline)
                                .foregroundColor(Color(hex: "#FF4444"))
                            Spacer()
                            if isDeletingAccount {
                                ProgressView().tint(Color(hex: "#FF4444")).scaleEffect(0.8)
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(Color(white: 0.3))
                            }
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(Color(white: 0.05))
                        .cornerRadius(10)
                    }
                    .disabled(isDeletingAccount)

                    // Versão
                    Text("PPPIX iOS v1.0.0")
                        .font(.caption)
                        .foregroundColor(Color(white: 0.2))

                    // Diagnóstico de alertas
                    Button {
                        showDiagnostic = true
                    } label: {
                        HStack {
                            Image(systemName: "stethoscope")
                                .foregroundColor(Color(hex: "#FF9900"))
                                .font(.system(size: 14))
                            Text("Diagnóstico de Alertas")
                                .font(.subheadline)
                                .foregroundColor(Color(hex: "#FF9900"))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(Color(white: 0.3))
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(Color(white: 0.05))
                        .cornerRadius(10)
                    }

                    // Logout
                    PPPIXButton(title: "Sair da Conta", style: .destructive) {
                        showLogoutConfirm = true
                    }

                    Spacer(minLength: 32)
                }
                .padding(.horizontal, 20)
            }
        }
        .navigationTitle("Perfil")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if isLoadingFresh {
                    ProgressView().tint(Color(white: 0.5)).scaleEffect(0.8)
                }
            }
        }
        .task { await loadFreshProfile() }
        .sheet(isPresented: $showDiagnostic) { AlertDiagnosticView() }
        .confirmationDialog("Sair da Conta", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
            Button("Sair", role: .destructive) { logout() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Deseja sair da sua conta PPPIX?")
        }
        .confirmationDialog(
            "Excluir conta permanentemente?",
            isPresented: $showDeleteAccountConfirm,
            titleVisibility: .visible
        ) {
            Button("Excluir minha conta", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Essa ação é irreversível. Seus dados pessoais (nome, email, CPF, telefone, veículos e contatos) serão removidos permanentemente. Você será desconectado e não poderá mais acessar essa conta.")
        }
        .alert("Erro ao excluir conta", isPresented: .constant(!deleteAccountError.isEmpty)) {
            Button("OK") { deleteAccountError = "" }
        } message: {
            Text(deleteAccountError)
        }
    }

    // MARK: - Actions

    private func loadFreshProfile() async {
        isLoadingFresh = true
        defer { isLoadingFresh = false }
        guard let me = try? await APIClient.shared.getMe() else { return }
        SessionManager.shared.saveUserInfo(id: me.id, email: me.email, name: me.fullName)
    }

    private func logout() {
        SessionManager.shared.clearSession()
    }

    private func deleteAccount() async {
        isDeletingAccount = true
        do {
            try await APIClient.shared.deleteAccount()
            isDeletingAccount = false
            SessionManager.shared.clearSession()
        } catch {
            isDeletingAccount = false
            deleteAccountError = "Não foi possível excluir sua conta agora. Verifique sua internet e tente novamente."
        }
    }
}

// MARK: - Sub-views

private struct ProfileInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(Color(white: 0.5))
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .padding(.vertical, 12)
    }
}

private struct ProfileLinkRow: View {
    let icon: String
    let title: String
    let url: String
    var color: Color = Color(hex: "#3366FF")

    var body: some View {
        if let link = URL(string: url) {
            Link(destination: link) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(color)
                        .font(.system(size: 16))
                        .frame(width: 24)
                    Text(title)
                        .font(.subheadline)
                        .foregroundColor(color)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundColor(Color(white: 0.3))
                }
                .padding(.vertical, 12)
            }
        }
    }
}
