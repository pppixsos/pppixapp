import SwiftUI

struct HomeView: View {

    @ObservedObject private var session = SessionManager.shared
    @ObservedObject private var premium = PremiumManager.shared
    @State private var showAlertDetail: Int? = nil
    @State private var showDisclaimer = false
    @State private var showInstallTutorial = false
    @State private var showPremiumOffer = false
    @State private var comingSoonFeature: ComingSoonFeature? = nil

    enum ComingSoonFeature: Identifiable {
        case personalTracker, vehicleTracker
        var id: Self { self }

        var icon: String {
            switch self {
            case .personalTracker: return "person.badge.shield.checkmark.fill"
            case .vehicleTracker:  return "car.rear.and.tire.marks"
            }
        }
        var title: String {
            switch self {
            case .personalTracker: return "Rastreamento Individual"
            case .vehicleTracker:  return "Rastreamento Veicular"
            }
        }
        var description: String {
            switch self {
            case .personalTracker:
                return "Em breve você poderá vincular um rastreador pessoal diretamente ao PPPIX. Seu grupo de emergência saberá sua localização exata em tempo real, mesmo sem precisar acionar o alerta manualmente."
            case .vehicleTracker:
                return "Em breve você poderá vincular o rastreador do seu veículo ao PPPIX. Em caso de roubo ou emergência, seu grupo de segurança acompanha a localização do seu carro em tempo real."
            }
        }
    }

    private var firstName: String {
        session.userName.split(separator: " ").first.map(String.init) ?? "Usuário"
    }

    private var gridColumns: [GridItem] {
        let count = UIDevice.current.userInterfaceIdiom == .pad ? 3 : 2
        return Array(repeating: GridItem(.flexible()), count: count)
    }

    private var maxContentWidth: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 700 : .infinity
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
                                        startPoint: .top, endPoint: .bottom
                                    )
                                )
                        }
                        .padding(.top, 8)

                        // Grid de cards ativos
                        LazyVGrid(columns: gridColumns, spacing: 12) {
                            HomeCard(icon: "lock.shield.fill", title: "Senhas",
                                     subtitle: "Configurar", color: Color(hex: "#3366FF"),
                                     destination: PasswordSetupView())
                            HomeCard(icon: "apps.iphone", title: "Apps",
                                     subtitle: "Bloquear", color: Color(hex: "#6633FF"),
                                     destination: AppListView())
                            HomeCard(icon: "person.2.fill", title: "Contatos",
                                     subtitle: "Gerenciar", color: Color(hex: "#0099FF"),
                                     destination: ContactsView())
                            HomeCard(icon: "car.fill", title: "Veículos",
                                     subtitle: "Meus carros", color: Color(hex: "#FF6600"),
                                     destination: VehiclesView())
                            HomeCard(icon: "bell.badge.fill", title: "Alertas",
                                     subtitle: "Histórico", color: Color(hex: "#FF3333"),
                                     destination: AlertsView())
                            HomeCard(icon: "checkmark.shield.fill", title: "Permissões",
                                     subtitle: "Configurar", color: Color(hex: "#00CC66"),
                                     destination: PermissionsView())
                        }

                        // Seção Em Breve
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Text("EM BREVE")
                                    .font(.system(size: 11, weight: .black))
                                    .foregroundColor(Color(white: 0.35))
                                    .kerning(1.5)
                                Rectangle()
                                    .fill(Color(white: 0.12))
                                    .frame(height: 1)
                            }

                            LazyVGrid(columns: gridColumns, spacing: 12) {
                                ComingSoonCard(
                                    feature: .personalTracker,
                                    onTap: { comingSoonFeature = .personalTracker }
                                )
                                ComingSoonCard(
                                    feature: .vehicleTracker,
                                    onTap: { comingSoonFeature = .vehicleTracker }
                                )
                            }
                        }

                        // Botão Tutorial
                        Button { showInstallTutorial = true } label: {
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
                    .frame(maxWidth: maxContentWidth)
                    .frame(maxWidth: .infinity)
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
        .sheet(item: $showAlertDetail) { alertId in AlertDetailView(alertId: alertId) }
        .onAppear {
            if DisclaimerPopup.shouldShow {
                showDisclaimer = true
            } else if !premium.isPremium {
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
        .sheet(isPresented: $showInstallTutorial) { InstallTutorialView() }
        .sheet(item: $comingSoonFeature) { feature in
            ComingSoonSheet(feature: feature)
        }
    }
}

// MARK: - Coming Soon Card

private struct ComingSoonCard: View {
    let feature: HomeView.ComingSoonFeature
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: feature.icon)
                        .font(.system(size: 28))
                        .foregroundColor(Color(white: 0.25))

                    Text("BREVE")
                        .font(.system(size: 8, weight: .black))
                        .foregroundColor(Color(white: 0.35))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color(white: 0.1))
                        .cornerRadius(4)
                        .offset(x: 6, y: -4)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(feature.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(white: 0.3))
                    Text("Em breve")
                        .font(.caption)
                        .foregroundColor(Color(white: 0.2))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(white: 0.04))
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color(white: 0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Coming Soon Sheet

private struct ComingSoonSheet: View {
    let feature: HomeView.ComingSoonFeature
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color(hex: "#0A0A12").ignoresSafeArea()

            VStack(spacing: 0) {
                // Puxador
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(white: 0.2))
                    .frame(width: 40, height: 5)
                    .padding(.top, 12)

                Spacer()

                VStack(spacing: 24) {
                    // Ícone com brilho
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [Color(hex: "#3366FF").opacity(0.2), .clear],
                                    center: .center, startRadius: 0, endRadius: 50
                                )
                            )
                            .frame(width: 100, height: 100)

                        Image(systemName: feature.icon)
                            .font(.system(size: 48))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(hex: "#6688FF"), Color(hex: "#4455DD")],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                    }

                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            Text("EM BREVE")
                                .font(.system(size: 11, weight: .black))
                                .foregroundColor(Color(hex: "#3366FF"))
                                .kerning(2)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color(hex: "#3366FF").opacity(0.12))
                                .cornerRadius(6)
                        }

                        Text(feature.title)
                            .font(.title2.bold())
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)

                        Text(feature.description)
                            .font(.subheadline)
                            .foregroundColor(Color(white: 0.5))
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .padding(.horizontal, 20)
                    }

                    // Linha de status
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color(hex: "#3366FF"))
                            .frame(width: 8, height: 8)
                            .overlay(
                                Circle()
                                    .fill(Color(hex: "#3366FF").opacity(0.3))
                                    .frame(width: 16, height: 16)
                            )
                        Text("Em desenvolvimento")
                            .font(.caption)
                            .foregroundColor(Color(white: 0.4))
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 20)
                    .background(Color(white: 0.05))
                    .cornerRadius(12)
                    .padding(.horizontal, 40)
                }

                Spacer()

                Button { dismiss() } label: {
                    Text("Entendi")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color(white: 0.1))
                        .cornerRadius(14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color(white: 0.12), lineWidth: 1)
                        )
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 36)
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Helpers

private struct ClearSheetBackground: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        DispatchQueue.main.async { view.superview?.backgroundColor = .clear }
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

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
