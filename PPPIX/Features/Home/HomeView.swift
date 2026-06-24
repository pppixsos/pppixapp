import SwiftUI

struct HomeView: View {

    @ObservedObject private var session = SessionManager.shared
    @ObservedObject private var premium = PremiumManager.shared
    @State private var showAlertDetail: Int? = nil
    @State private var showDisclaimer = false
    @State private var showInstallTutorial = false
    @State private var showPremiumOffer = false

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

                        // Botão Tutorial de Instalação (full-width, estilo YouTube)
                        Button {
                            showInstallTutorial = true
                        } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.white.opacity(0.15))
                                        .frame(width: 44, height: 44)
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 17))
                                        .foregroundColor(.white)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Tutorial de instalação")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.white)
                                    Text("Veja como configurar tudo corretamente")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.85))
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.85))
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity)
                            .background(
                                LinearGradient(
                                    colors: [Color(hex: "#FF0000"), Color(hex: "#CC0000")],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
                            )
                            .shadow(color: Color(hex: "#FF0000").opacity(0.35), radius: 12, x: 0, y: 6)
                        }
                        .buttonStyle(.plain)

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
        .onAppear {
            if DisclaimerPopup.shouldShow {
                showDisclaimer = true
            } else if !premium.isPremium {
                // Mostra oferta premium toda vez que abre o app (só para free)
                showPremiumOffer = true
            }
        }
        .sheet(isPresented: $showDisclaimer) {
            DisclaimerPopupView(onAccept: { showDisclaimer = false })
                .background(ClearSheetBackground())
        }
        .fullScreenCover(isPresented: $showPremiumOffer) {
            PremiumPaywallView(onClose: { showPremiumOffer = false })
        }
        .sheet(isPresented: $showInstallTutorial) {
            InstallTutorialView()
        }
    }
}

/// Torna o fundo do sheet transparente — compatível com iOS 16.0+
/// (presentationBackground só existe a partir do iOS 16.4).
private struct ClearSheetBackground: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        DispatchQueue.main.async { view.superview?.backgroundColor = .clear }
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
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
