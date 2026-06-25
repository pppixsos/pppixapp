import SwiftUI

struct ContactsView: View {

    // Separados por tipo para nunca confundir "enviado" com "recebido"
    @State private var accepted:  [Connection] = []
    @State private var received:  [Connection] = []  // convites QUE EU RECEBI
    @State private var sent:      [Connection] = []  // convites QUE EU ENVIEI
    @State private var externalContacts: [APIClient.ExternalContact] = []  // sem conta, recebem so' via WhatsApp
    @State private var isLoading  = true
    @State private var showAddSheet = false
    @State private var errorMessage = ""
    @State private var successMessage = ""
    @State private var showPaywall = false
    @ObservedObject private var premium = PremiumManager.shared
    private var myEmail: String { SessionManager.shared.userEmail }

    // Conta TODOS os contatos — aceitos, pendentes enviados, pendentes recebidos
    // e externos. No plano free a pessoa tem direito a 1 vaga total, seja ela
    // ocupada por quem for. Se o convite não foi aceito, a vaga continua ocupada
    // até que o contato seja removido.
    private var totalContacts: Int {
        accepted.count + externalContacts.count + sent.count + received.count
    }
    private var atLimit: Bool { !premium.isPremium && totalContacts >= PremiumManager.freeContactLimit }

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
                            Text(successMessage).font(.footnote)
                                .foregroundColor(Color(hex: "#44FF88"))
                                .multilineTextAlignment(.center)
                        }
                        if !errorMessage.isEmpty { ErrorBanner(message: errorMessage) }

                        // Banner Premium — aparece quando atingiu o limite
                        if atLimit {
                            PremiumBanner(
                                message: "Quer adicionar mais contatos de emergência? Contrate o Premium",
                                onTap: { showPaywall = true }
                            )
                        }

                        // CONVITES RECEBIDOS (aguardando minha resposta)
                        if !received.isEmpty {
                            sectionHeader("Convites Recebidos", icon: "envelope.badge.fill", color: Color(hex: "#FF9900"))
                            ForEach(received) { conn in
                                ConnectionRow(
                                    connection: conn,
                                    myEmail: myEmail,
                                    rowType: .received,
                                    onAccept: { Task { await acceptConnection(conn) } },
                                    onDelete: { Task { await deleteConnection(conn) } }
                                )
                            }
                        }

                        // CONVITES ENVIADOS (aguardando resposta do outro)
                        if !sent.isEmpty {
                            sectionHeader("Aguardando Resposta", icon: "clock.fill", color: Color(hex: "#8888FF"))
                            ForEach(sent) { conn in
                                ConnectionRow(
                                    connection: conn,
                                    myEmail: myEmail,
                                    rowType: .sent,
                                    onAccept: {},
                                    onDelete: { Task { await deleteConnection(conn) } }
                                )
                            }
                        }

                        // CONTATOS ACEITOS
                        if !accepted.isEmpty {
                            sectionHeader("Contatos Ativos", icon: "checkmark.shield.fill", color: Color(hex: "#44FF88"))
                            ForEach(accepted) { conn in
                                ConnectionRow(
                                    connection: conn,
                                    myEmail: myEmail,
                                    rowType: .accepted,
                                    onAccept: {},
                                    onDelete: { Task { await deleteConnection(conn) } }
                                )
                            }
                        }

                        // CONTATOS EXTERNOS (sem conta — alertas via WhatsApp)
                        if !externalContacts.isEmpty {
                            sectionHeader("Contatos via WhatsApp", icon: "phone.fill", color: Color(hex: "#25D366"))
                            ForEach(externalContacts) { contact in
                                ExternalContactRow(contact: contact) {
                                    Task { await deleteExternalContact(contact) }
                                }
                            }
                        }

                        if accepted.isEmpty && received.isEmpty && sent.isEmpty && externalContacts.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "person.badge.plus")
                                    .font(.system(size: 48))
                                    .foregroundColor(Color(white: 0.3))
                                Text("Nenhum contato de emergência")
                                    .foregroundColor(Color(white: 0.4))
                                Text("Adicione pessoas de confiança que receberão alertas caso você precise de ajuda")
                                    .font(.caption).foregroundColor(Color(white: 0.3))
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.vertical, 32)
                        }

                        Spacer(minLength: 80)
                    }
                    .padding(.horizontal, 20).padding(.top, 16)
                    .frame(maxWidth: 680)
                    .frame(maxWidth: .infinity)
                }
            }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        if atLimit {
                            showPaywall = true
                        } else {
                            showAddSheet = true
                        }
                    } label: {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(atLimit ? Color(white: 0.4) : .white)
                            .frame(width: 56, height: 56)
                            .background(Group {
                                if atLimit {
                                    Color(white: 0.15)
                                } else {
                                    LinearGradient(
                                        colors: [Color(hex: "#3366FF"), Color(hex: "#6633FF")],
                                        startPoint: .topLeading, endPoint: .bottomTrailing)
                                }
                            })
                            .clipShape(Circle())
                            .shadow(color: atLimit ? .clear : Color(hex: "#3366FF").opacity(0.5), radius: 8)
                    }
                    .padding(.trailing, 24).padding(.bottom, 24)
                }
            }
        }
        .navigationTitle("Contatos de Emergência")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddSheet) {
            AddContactSheet(myEmail: myEmail, allowWhatsApp: premium.isPremium) { msg in
                successMessage = msg
                errorMessage = ""
                Task { await loadContacts() }
            }
        }
        .fullScreenCover(isPresented: $showPaywall) {
            PremiumPaywallView(onClose: { showPaywall = false })
        }
        .task { await loadContacts() }
        .refreshable { await loadContacts() }
    }

    private func sectionHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 12)).foregroundColor(color)
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundColor(color)
            Spacer()
        }
        .padding(.horizontal, 4).padding(.top, 4)
    }

    private func loadContacts() async {
        isLoading = true
        errorMessage = ""
        defer { isLoading = false }

        do {
            // Busca os 3 grupos em paralelo
            async let accTask  = APIClient.shared.getAcceptedConnections()
            async let pendTask = APIClient.shared.getPendingConnections()

            let accResult  = (try? await accTask)  ?? []
            let pendResult = (try? await pendTask) ?? []

            // Separa enviados dos recebidos pelo email
            let myLower = myEmail.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let recv = pendResult.filter {
                $0.to_user_email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == myLower
            }
            let snt = pendResult.filter {
                $0.to_user_email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) != myLower
            }

            // Tenta também o endpoint de recebidos dedicado e mescla sem duplicatas.
            // IMPORTANTE: o fallback de getReceivedConnectionRequests() retorna
            // TODAS as pendentes (enviadas E recebidas), pois o endpoint dedicado
            // /connections/received/ nao existe no backend. Por isso filtramos
            // por direcao aqui tambem, senao convites ENVIADOS por mim aparecem
            // erroneamente como "Convite Recebido".
            let recvExtraRaw = (try? await APIClient.shared.getReceivedConnectionRequests()) ?? []
            let recvExtra = recvExtraRaw.filter {
                $0.to_user_email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == myLower
            }
            let recvIds = Set(recv.map { $0.id })
            let merged = recv + recvExtra.filter { !recvIds.contains($0.id) }

            accepted = accResult
            received = merged
            sent     = snt
            externalContacts = (try? await APIClient.shared.fetchExternalContacts()) ?? []

        } catch {
            errorMessage = "Erro ao carregar: \(error.localizedDescription)"
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

    private func deleteExternalContact(_ c: APIClient.ExternalContact) async {
        do {
            try await APIClient.shared.deleteExternalContact(id: c.id)
            await loadContacts()
        } catch {
            errorMessage = "Erro ao remover contato."
        }
    }
}

// MARK: - External Contact Row (sem conta, WhatsApp)

private struct ExternalContactRow: View {
    let contact: APIClient.ExternalContact
    let onDelete: () -> Void
    @State private var showDeleteConfirm = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "phone.circle.fill")
                .font(.system(size: 32))
                .foregroundColor(Color(hex: "#25D366"))
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name).font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                Text(contact.phone).font(.caption).foregroundColor(Color(white: 0.5))
                Text("Recebe alertas via WhatsApp").font(.caption2).foregroundColor(Color(hex: "#25D366"))
            }
            Spacer()
            Button { showDeleteConfirm = true } label: {
                Image(systemName: "trash").foregroundColor(Color(white: 0.4))
            }
        }
        .padding(12)
        .background(Color(white: 0.08))
        .cornerRadius(12)
        .confirmationDialog("Remover \(contact.name)?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Remover", role: .destructive, action: onDelete)
            Button("Cancelar", role: .cancel) {}
        }
    }
}

// MARK: - Row

enum ConnectionRowType { case received, sent, accepted }

private struct ConnectionRow: View {
    let connection: Connection
    let myEmail: String
    let rowType: ConnectionRowType
    let onAccept: () -> Void
    let onDelete: () -> Void

    @State private var showDeleteConfirm = false

    private var displayName: String { connection.displayName(myEmail: myEmail) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                // Avatar
                Text(String(displayName.prefix(1)).uppercased())
                    .font(.system(size: 18, weight: .bold)).foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(avatarColor).clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                    Text(connection.displayEmail(myEmail: myEmail))
                        .font(.caption).foregroundColor(Color(white: 0.5))
                }

                Spacer()

                // Badge de status
                Text(statusLabel)
                    .font(.caption2.bold()).foregroundColor(statusColor)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(statusColor.opacity(0.15)).cornerRadius(6)
            }

            HStack(spacing: 10) {
                // Botão ACEITAR — só aparece quando EU recebi o convite
                if rowType == .received {
                    Button(action: onAccept) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                            Text("Aceitar Convite").font(.system(size: 13, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(Color(hex: "#228B22")).cornerRadius(10)
                    }
                }

                Spacer()

                Button { showDeleteConfirm = true } label: {
                    Text(rowType == .accepted ? "Remover" : "Cancelar")
                        .font(.caption.bold()).foregroundColor(Color(hex: "#FF4444"))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color(hex: "#FF4444").opacity(0.1)).cornerRadius(8)
                }
            }
        }
        .padding(16)
        .background(Color(hex: "#141422")).cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(borderColor.opacity(0.25), lineWidth: 1))
        .confirmationDialog(
            rowType == .accepted ? "Remover contato?" : "Cancelar convite?",
            isPresented: $showDeleteConfirm, titleVisibility: .visible
        ) {
            Button(rowType == .accepted ? "Remover \(displayName)" : "Cancelar Convite",
                   role: .destructive, action: onDelete)
            Button("Voltar", role: .cancel) {}
        }
    }

    private var statusLabel: String {
        switch rowType {
        case .received: return "Convite Recebido"
        case .sent:     return "Aguardando"
        case .accepted: return "Aceito ✓"
        }
    }
    private var statusColor: Color {
        switch rowType {
        case .received: return Color(hex: "#FF9900")
        case .sent:     return Color(hex: "#8888FF")
        case .accepted: return Color(hex: "#44FF88")
        }
    }
    private var avatarColor: Color {
        switch rowType {
        case .received: return Color(hex: "#FF9900")
        case .sent:     return Color(white: 0.3)
        case .accepted: return Color(hex: "#3366FF")
        }
    }
    private var borderColor: Color {
        switch rowType {
        case .received: return Color(hex: "#FF9900")
        case .sent:     return Color(hex: "#8888FF")
        case .accepted: return Color(hex: "#3366FF")
        }
    }
}

// MARK: - Add Contact Sheet

private enum ContactMethod {
    case email, phone
}

private struct AddContactSheet: View {
    let myEmail: String
    var allowWhatsApp: Bool = true
    let onSent: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var method: ContactMethod? = nil

    @State private var email = ""
    @State private var contactName = ""
    @State private var phone = ""

    @State private var isSending = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0A0A12").ignoresSafeArea()

                if method == nil {
                    // Tela de escolha: Email (pessoa com app) ou Telefone (sem app)
                    VStack(spacing: 24) {
                        VStack(spacing: 8) {
                            Image(systemName: "person.crop.circle.badge.plus").font(.system(size: 44))
                                .foregroundColor(Color(hex: "#3366FF"))
                            Text("Adicionar Contato de Emergência").font(.title2.bold()).foregroundColor(.white)
                            Text("Essa pessoa já tem o PPPIX instalado?")
                                .font(.subheadline).foregroundColor(Color(white: 0.5))
                                .multilineTextAlignment(.center)
                        }

                        Button { method = .email } label: {
                            optionRow(icon: "envelope.badge.fill",
                                      title: "Sim, tem o PPPIX",
                                      subtitle: "Adicionar pelo email — recebe alertas pelo app e WhatsApp",
                                      locked: false)
                        }

                        if allowWhatsApp {
                            Button { method = .phone } label: {
                                optionRow(icon: "phone.badge.plus",
                                          title: "Não, não tem o app",
                                          subtitle: "Adicionar pelo nome e telefone — recebe alertas pelo WhatsApp",
                                          locked: false)
                            }
                        } else {
                            optionRow(icon: "phone.badge.plus",
                                      title: "Não, não tem o app",
                                      subtitle: "🔒 Premium — recebe alertas pelo WhatsApp",
                                      locked: true)
                        }

                        Spacer()
                    }
                    .padding(24)
                } else if method == .email {
                    VStack(spacing: 24) {
                        VStack(spacing: 8) {
                            Image(systemName: "envelope.badge.fill").font(.system(size: 44))
                                .foregroundColor(Color(hex: "#3366FF"))
                            Text("Adicionar por Email").font(.title2.bold()).foregroundColor(.white)
                            Text("A pessoa precisa ter o PPPIX instalado")
                                .font(.subheadline).foregroundColor(Color(white: 0.5))
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
                } else {
                    VStack(spacing: 24) {
                        VStack(spacing: 8) {
                            Image(systemName: "phone.badge.plus").font(.system(size: 44))
                                .foregroundColor(Color(hex: "#3366FF"))
                            Text("Adicionar por Telefone").font(.title2.bold()).foregroundColor(.white)
                            Text("Essa pessoa receberá os alertas de emergência via WhatsApp")
                                .font(.subheadline).foregroundColor(Color(white: 0.5))
                                .multilineTextAlignment(.center)
                        }
                        PPPIXTextField(title: "Nome do Contato", placeholder: "Ex: Maria Silva",
                                      text: $contactName, autocapitalization: .words)
                        PPPIXTextField(title: "Telefone (com DDD e país)", placeholder: "+5527999998888",
                                      text: $phone, keyboardType: .phonePad)
                        if !errorMessage.isEmpty { ErrorBanner(message: errorMessage) }
                        PPPIXButton(title: "Adicionar Contato", isLoading: isSending) {
                            Task { await addPhoneContact() }
                        }
                        Spacer()
                    }
                    .padding(24)
                }
            }
            .navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(method == nil ? "Cancelar" : "Voltar") {
                        if method == nil {
                            dismiss()
                        } else {
                            method = nil
                            errorMessage = ""
                        }
                    }.foregroundColor(Color(white: 0.6))
                }
            }
        }
    }

    private func optionRow(icon: String, title: String, subtitle: String, locked: Bool = false) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 28))
                .foregroundColor(locked ? Color(white: 0.3) : Color(hex: "#3366FF"))
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                    .foregroundColor(locked ? Color(white: 0.3) : .white)
                Text(subtitle).font(.caption)
                    .foregroundColor(locked ? Color(white: 0.25) : Color(white: 0.5))
                    .multilineTextAlignment(.leading)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundColor(locked ? Color(white: 0.2) : Color(white: 0.4))
        }
        .padding(16)
        .background(Color(white: locked ? 0.04 : 0.1))
        .cornerRadius(12)
        .opacity(locked ? 0.7 : 1.0)
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
            let l = msg.lowercased()
            errorMessage = (l.contains("already") || l.contains("pending"))
                ? "Você já tem uma conexão com este contato." : msg
        } catch APIError.notFound {
            errorMessage = "Email não encontrado. Verifique se a pessoa tem o PPPIX."
        } catch {
            errorMessage = "Erro de conexão. Verifique sua internet."
        }
        isSending = false
    }

    private func addPhoneContact() async {
        let trimmedName = contactName.trimmingCharacters(in: .whitespaces)
        var trimmedPhone = phone.trimmingCharacters(in: .whitespaces)
        trimmedPhone = trimmedPhone.filter { $0.isNumber || $0 == "+" }

        if trimmedName.isEmpty { errorMessage = "Digite o nome do contato."; return }
        if trimmedPhone.count < 8 { errorMessage = "Telefone inválido. Use o formato +5527999998888."; return }

        isSending = true
        do {
            try await APIClient.shared.addExternalContact(name: trimmedName, phone: trimmedPhone)
            onSent("\(trimmedName) adicionado(a) como contato de emergência!")
            dismiss()
        } catch {
            errorMessage = "Erro ao adicionar contato. Verifique sua internet."
        }
        isSending = false
    }
}

extension Connection {
    func displayEmail(myEmail: String) -> String {
        to_user_email.lowercased() == myEmail.lowercased() ? from_user_email : to_user_email
    }
    func isRecipient(myEmail: String) -> Bool {
        to_user_email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            == myEmail.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
