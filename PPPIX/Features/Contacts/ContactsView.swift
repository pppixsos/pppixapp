import SwiftUI

struct ContactsView: View {

    @State private var connections: [Connection] = []
    @State private var isLoading = true
    @State private var showAddSheet = false
    @State private var errorMessage = ""
    @State private var successMessage = ""
    private var myEmail: String { SessionManager.shared.userEmail }

    var body: some View {
        ZStack {
            Color(hex: "#0A0A12").ignoresSafeArea()

            if isLoading {
                ProgressView().tint(Color(hex: "#3366FF"))
            } else {
                ScrollView {
                    VStack(spacing: 16) {

                        PPPIXCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Grupo de Emergência", systemImage: "person.2.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(Color(hex: "#3366FF"))
                                Text("Estes contatos receberão alertas quando você usar a senha de emergência.")
                                    .font(.caption)
                                    .foregroundColor(Color(white: 0.6))
                            }
                        }

                        if !successMessage.isEmpty {
                            Text(successMessage)
                                .font(.footnote)
                                .foregroundColor(Color(hex: "#44FF88"))
                                .multilineTextAlignment(.center)
                        }
                        if !errorMessage.isEmpty {
                            ErrorBanner(message: errorMessage)
                        }

                        if connections.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "person.badge.plus")
                                    .font(.system(size: 48))
                                    .foregroundColor(Color(white: 0.3))
                                Text("Nenhum contato de emergência")
                                    .foregroundColor(Color(white: 0.4))
                                Text("Adicione pessoas de confiança que receberão alertas caso você precise de ajuda")
                                    .font(.caption)
                                    .foregroundColor(Color(white: 0.3))
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.vertical, 32)
                        } else {
                            ForEach(connections) { connection in
                                ConnectionRow(
                                    connection: connection,
                                    myEmail: myEmail,
                                    onAccept: { Task { await acceptConnection(connection) } },
                                    onDelete: { Task { await deleteConnection(connection) } }
                                )
                            }
                        }

                        Spacer(minLength: 80)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button { showAddSheet = true } label: {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 56, height: 56)
                            .background(
                                LinearGradient(
                                    colors: [Color(hex: "#3366FF"), Color(hex: "#6633FF")],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )
                            .clipShape(Circle())
                            .shadow(color: Color(hex: "#3366FF").opacity(0.5), radius: 8)
                    }
                    .padding(.trailing, 24)
                    .padding(.bottom, 24)
                }
            }
        }
        .navigationTitle("Contatos de Emergência")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddSheet) {
            AddContactSheet(myEmail: myEmail) { msg in
                successMessage = msg
                errorMessage = ""
                Task { await loadContacts() }
            }
        }
        .task { await loadContacts() }
        .refreshable { await loadContacts() }
    }

    private func loadContacts() async {
        isLoading = true
        errorMessage = ""
        defer { isLoading = false }

        do {
            let accepted = try await APIClient.shared.getAcceptedConnections()
            let pending  = try await APIClient.shared.getPendingConnections()
            connections = pending + accepted
        } catch {
            errorMessage = "Erro ao carregar: \(error.localizedDescription)"
            connections = []
        }
    }

    private func acceptConnection(_ c: Connection) async {
        do {
            try await APIClient.shared.acceptConnection(id: c.id)
            successMessage = "Contato aceito!"
            errorMessage = ""
            await loadContacts()
        } catch {
            errorMessage = "Erro ao aceitar: \(error.localizedDescription)"
        }
    }

    private func deleteConnection(_ c: Connection) async {
        do {
            try await APIClient.shared.deleteConnection(id: c.id)
            await loadContacts()
        } catch {
            errorMessage = "Erro ao remover contato."
        }
    }
}

// MARK: - ConnectionRow

private struct ConnectionRow: View {
    let connection: Connection
    let myEmail: String
    let onAccept: () -> Void
    let onDelete: () -> Void

    @State private var showDeleteConfirm = false

    private var isPending: Bool { connection.status == "pending" }
    private var isReceived: Bool { connection.isRecipient(myEmail: myEmail) && isPending }
    private var displayName: String { connection.displayName(myEmail: myEmail) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(displayName.prefix(1)).uppercased())
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(isPending ? Color(white: 0.3) : Color(hex: "#3366FF"))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    Text(connection.displayEmail(myEmail: myEmail))
                        .font(.caption)
                        .foregroundColor(Color(white: 0.5))
                }

                Spacer()

                Text(isPending ? (isReceived ? "Convite Recebido" : "Aguardando") : "Aceito ✓")
                    .font(.caption2.bold())
                    .foregroundColor(isPending ? Color(hex: "#FF9900") : Color(hex: "#44FF88"))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isPending ? Color(hex: "#FF9900").opacity(0.15) : Color(hex: "#44FF88").opacity(0.15))
                    .cornerRadius(6)
            }

            HStack(spacing: 10) {
                if isReceived {
                    Button(action: onAccept) {
                        Label("Aceitar", systemImage: "checkmark")
                            .font(.caption.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color(hex: "#228B22"))
                            .cornerRadius(8)
                    }
                }
                Spacer()
                Button { showDeleteConfirm = true } label: {
                    Text(isPending ? "Cancelar" : "Remover")
                        .font(.caption.bold())
                        .foregroundColor(Color(hex: "#FF4444"))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color(hex: "#FF4444").opacity(0.1))
                        .cornerRadius(8)
                }
            }
        }
        .padding(16)
        .background(Color(hex: "#141422"))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(isPending ? Color(hex: "#FF9900").opacity(0.2) : Color(hex: "#3366FF").opacity(0.2), lineWidth: 1))
        .confirmationDialog(isPending ? "Cancelar convite?" : "Remover contato?",
                           isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button(isPending ? "Cancelar Convite" : "Remover \(displayName)", role: .destructive, action: onDelete)
            Button("Voltar", role: .cancel) {}
        }
    }
}

// MARK: - AddContactSheet

private struct AddContactSheet: View {
    let myEmail: String
    let onSent: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var isSending = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0A0A12").ignoresSafeArea()
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Image(systemName: "envelope.badge.fill")
                            .font(.system(size: 44))
                            .foregroundColor(Color(hex: "#3366FF"))
                        Text("Adicionar Contato")
                            .font(.title2.bold())
                            .foregroundColor(.white)
                        Text("A pessoa precisa ter o PPPIX instalado (iOS ou Android)")
                            .font(.subheadline)
                            .foregroundColor(Color(white: 0.5))
                            .multilineTextAlignment(.center)
                    }
                    PPPIXTextField(title: "Email do Contato", placeholder: "email@exemplo.com",
                                  text: $email, keyboardType: .emailAddress, autocapitalization: .never)
                    if !errorMessage.isEmpty { ErrorBanner(message: errorMessage) }
                    PPPIXButton(title: "Enviar Convite", isLoading: isSending) {
                        Task { await sendInvite() }
                    }
                    Spacer()
                }
                .padding(24)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancelar") { dismiss() }.foregroundColor(Color(white: 0.6))
                }
            }
        }
    }

    private func sendInvite() async {
        let trimmed = email.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed.isEmpty { errorMessage = "Digite o email do contato."; return }
        if !trimmed.contains("@") { errorMessage = "Email inválido."; return }
        if trimmed == myEmail.lowercased() { errorMessage = "Você não pode adicionar a si mesmo."; return }

        isSending = true
        do {
            try await APIClient.shared.sendConnectionRequest(email: trimmed)
            onSent("Convite enviado para \(trimmed)!")
            dismiss()
        } catch APIError.badRequest(let msg) {
            let lower = msg.lowercased()
            if lower.contains("already") || lower.contains("already_connected") || lower.contains("pending") {
                errorMessage = "Você já tem uma conexão com este contato."
            } else {
                errorMessage = msg
            }
        } catch APIError.notFound {
            errorMessage = "Email não encontrado. Verifique se a pessoa tem o PPPIX."
        } catch {
            errorMessage = "Erro de conexão. Verifique sua internet."
        }
        isSending = false
    }
}

extension Connection {
    func displayEmail(myEmail: String) -> String {
        to_user_email.lowercased() == myEmail.lowercased() ? from_user_email : to_user_email
    }
    func isRecipient(myEmail: String) -> Bool {
        to_user_email.lowercased() == myEmail.lowercased()
    }
}
