import SwiftUI
import UserNotifications

struct HomeView: View {

    @ObservedObject private var session = SessionManager.shared
    @State private var showAlertDetail: Int? = nil

    private var firstName: String {
        session.userName.split(separator: " ").first.map(String.init) ?? "Usuário"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0A0A12").ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {

                        // Header
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Olá, \(firstName) 👋")
                                    .font(.title2.bold())
                                    .foregroundColor(.white)
                                Text("Sua proteção está ativa")
                                    .font(.subheadline)
                                    .foregroundColor(Color(white: 0.5))
                            }
                            Spacer()
                            Image(systemName: "shield.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color(hex: "#3366FF"), Color(hex: "#6633FF")],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        }
                        .padding(.top, 8)

                        // Grid de cards
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 12) {
                            HomeCard(
                                icon: "lock.shield.fill",
                                title: "Senhas",
                                subtitle: "Configurar",
                                color: Color(hex: "#3366FF"),
                                destination: PasswordSetupView()
                            )
                            HomeCard(
                                icon: "apps.iphone",
                                title: "Apps",
                                subtitle: "Bloquear",
                                color: Color(hex: "#6633FF"),
                                destination: AppListView()
                            )
                            HomeCard(
                                icon: "person.2.fill",
                                title: "Contatos",
                                subtitle: "Gerenciar",
                                color: Color(hex: "#0099FF"),
                                destination: ContactsView()
                            )
                            HomeCard(
                                icon: "car.fill",
                                title: "Veículos",
                                subtitle: "Meus carros",
                                color: Color(hex: "#FF6600"),
                                destination: VehiclesView()
                            )
                            HomeCard(
                                icon: "bell.badge.fill",
                                title: "Alertas",
                                subtitle: "Histórico",
                                color: Color(hex: "#FF3333"),
                                destination: AlertsView()
                            )
                            HomeCard(
                                icon: "checkmark.shield.fill",
                                title: "Permissões",
                                subtitle: "Configurar",
                                color: Color(hex: "#00CC66"),
                                destination: PermissionsView()
                            )
                        }

                        // Botão de teste de notificação (DEBUG)
                        TestNotificationButton()

                        // Card Premium (aparece se não for premium)
                        PremiumCard()

                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: ProfileView()) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(Color(white: 0.7))
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .incomingEmergencyAlert)) { notif in
            if let alertId = notif.userInfo?["alert_id"] as? Int {
                showAlertDetail = alertId
            }
        }
        .sheet(item: $showAlertDetail) { alertId in
            AlertDetailView(alertId: alertId)
        }
    }
}

// MARK: - Home Card

private struct HomeCard<Dest: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let destination: Dest

    var body: some View {
        NavigationLink(destination: destination) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundColor(color)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(Color(white: 0.5))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(hex: "#141422"))
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(color.opacity(0.2), lineWidth: 1)
            )
        }
    }
}

// MARK: - Premium Card

private struct PremiumCard: View {
    @State private var showSubscription = false

    var body: some View {
        // TODO: checar status premium via StoreKit
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
                Text("PPPIX Premium")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            Text("Remova os anúncios e suporte o desenvolvimento do app")
                .font(.subheadline)
                .foregroundColor(Color(white: 0.6))

            HStack(spacing: 12) {
                SubscriptionButton(title: "Mensal\nR$9,90") {
                    showSubscription = true
                }
                SubscriptionButton(title: "Anual\nR$79,90") {
                    showSubscription = true
                }
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color(hex: "#1A1033"), Color(hex: "#0A0A22")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(hex: "#6633FF").opacity(0.4), lineWidth: 1)
        )
        .sheet(isPresented: $showSubscription) {
            SubscriptionView()
        }
    }
}

private struct SubscriptionButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        colors: [Color(hex: "#3366FF"), Color(hex: "#6633FF")],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(8)
        }
    }
}

// MARK: - Test Notification Button (DEBUG)

private struct TestNotificationButton: View {
    @State private var isTesting = false
    @State private var result = ""

    var body: some View {
        VStack(spacing: 8) {
            Button(action: testNotification) {
                HStack(spacing: 10) {
                    if isTesting {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 16, weight: .bold))
                    }
                    Text(isTesting ? "Testando..." : "🔔 Testar Alerta")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(hex: "#FF3333"))
                .cornerRadius(12)
            }
            .disabled(isTesting)

            if !result.isEmpty {
                Text(result)
                    .font(.caption)
                    .foregroundColor(Color(white: 0.6))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 0)
    }

    private func testNotification() {
        isTesting = true
        result = ""

        Task { @MainActor in
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            let status = settings.authorizationStatus
            AlertDiagnosticLog.shared.log("TEST: permissão=\(status.rawValue) sound=\(settings.soundSetting.rawValue)")

            guard status == .authorized else {
                result = "Permissão negada (\(status.rawValue)). Vá em Ajustes > PPPIX > Notificações."
                isTesting = false
                return
            }

            let content = UNMutableNotificationContent()
            content.title = "🚨 TESTE — Alerta de Emergência"
            content.body = "Notificação de teste. Se você ver isso, está funcionando!"
            content.interruptionLevel = .timeSensitive

            if Bundle.main.url(forResource: "sirene", withExtension: "caf") != nil {
                content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: "sirene.caf"))
                result = "Usando sirene.caf — minimize o app agora!"
                AlertDiagnosticLog.shared.log("TEST: som=sirene.caf")
            } else if Bundle.main.url(forResource: "sirene", withExtension: "mp3") != nil {
                content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: "sirene.mp3"))
                result = "Usando sirene.mp3 — minimize o app agora!"
                AlertDiagnosticLog.shared.log("TEST: som=sirene.mp3")
            } else {
                content.sound = .default
                result = "Sem sirene no bundle — usando som padrão. Minimize o app!"
                AlertDiagnosticLog.shared.log("TEST: som=padrão (sirene não encontrada)")
            }

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
            let request = UNNotificationRequest(
                identifier: "pppix_test_\(Int(Date().timeIntervalSince1970))",
                content: content, trigger: trigger
            )
            do {
                try await UNUserNotificationCenter.current().add(request)
                AlertDiagnosticLog.shared.log("TEST: notificação agendada com sucesso ✅")
            } catch {
                result = "ERRO: \(error.localizedDescription)"
                AlertDiagnosticLog.shared.log("TEST: ERRO ao agendar: \(error)")
            }
            isTesting = false
        }
    }
}
