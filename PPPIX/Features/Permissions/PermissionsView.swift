import SwiftUI
import CoreLocation
import UserNotifications
#if !targetEnvironment(simulator)
import FamilyControls
#endif

struct PermissionsView: View {

    @StateObject private var viewModel = PermissionsViewModel()
    @State private var showDisclosure = false

    var body: some View {
        ZStack {
            Color(hex: "#0A0A12").ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {

                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(hex: "#00CC66"), Color(hex: "#3366FF")],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                        Text("Permissões do App")
                            .font(.title2.bold())
                            .foregroundColor(.white)
                        Text("Configure as permissões para o PPPIX funcionar corretamente")
                            .font(.subheadline)
                            .foregroundColor(Color(white: 0.5))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)

                    PermissionRow(
                        icon: "bell.badge.fill",
                        color: Color(hex: "#FF6600"),
                        title: "Notificações Push",
                        description: "Para receber alertas de emergência dos seus contatos",
                        status: viewModel.notificationsStatus,
                        onGrant: { Task { await viewModel.requestNotifications() } }
                    )

                    PermissionRow(
                        icon: "location.fill",
                        color: Color(hex: "#3366FF"),
                        title: "Localização",
                        description: "Envia sua posição GPS no alerta de emergência",
                        status: viewModel.locationStatus,
                        onGrant: { viewModel.requestLocation() }
                    )

                    PermissionRow(
                        icon: "location.fill.viewfinder",
                        color: Color(hex: "#0099FF"),
                        title: "Localização em Background",
                        description: "Permite enviar posição mesmo com tela bloqueada",
                        status: viewModel.locationBgStatus,
                        actionLabel: "Ajustes",
                        onGrant: { viewModel.requestLocationAlways() }
                    )

                    #if !targetEnvironment(simulator)
                    PermissionRow(
                        icon: "hourglass",
                        color: Color(hex: "#6633FF"),
                        title: "Screen Time (Bloqueio de Apps)",
                        description: "Necessário para bloquear apps financeiros com senha",
                        status: viewModel.screenTimeStatus,
                        errorMessage: viewModel.screenTimeError,
                        onGrant: { Task { await viewModel.requestScreenTime() } }
                    )
                    #endif

                    PermissionRow(
                        icon: "arrow.clockwise.circle.fill",
                        color: Color(hex: "#FF9900"),
                        title: "Background App Refresh",
                        description: "Mantém o app funcionando em segundo plano",
                        status: viewModel.backgroundRefreshStatus,
                        actionLabel: "Ajustes",
                        onGrant: {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    )

                    Button {
                        showDisclosure = true
                    } label: {
                        HStack {
                            Image(systemName: "doc.text.fill")
                                .foregroundColor(Color(hex: "#3366FF"))
                            Text("Ver Declaração de Privacidade")
                                .font(.subheadline)
                                .foregroundColor(Color(hex: "#3366FF"))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(hex: "#3366FF").opacity(0.1))
                        .cornerRadius(12)
                    }

                    Spacer(minLength: 32)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
        }
        .navigationTitle("Permissões")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.checkAll() }
        .alert("Declaração de Privacidade", isPresented: $showDisclosure) {
            Button("Entendi e Aceito") {
                SessionManager.shared.werePermissionsAsked = true
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("O PPPIX usa o Screen Time EXCLUSIVAMENTE para bloquear apps que você mesmo selecionar. A localização é coletada SOMENTE no alerta de emergência. Seus dados nunca são vendidos.")
        }
    }
}

private struct PermissionRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String
    let status: PermissionStatus
    var actionLabel: String = "Continuar"
    var errorMessage: String? = nil
    let onGrant: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundColor(color)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    Text(status == .granted ? "\(title): Concedido ✓" : description)
                        .font(.caption)
                        .foregroundColor(status == .granted ? Color(hex: "#44FF88") : Color(white: 0.5))
                }

                Spacer()

                if status == .granted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color(hex: "#44FF88"))
                        .font(.system(size: 20))
                } else {
                    Button(action: onGrant) {
                        Text(actionLabel)
                            .font(.caption.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(status == .denied ? Color(hex: "#FF6600") : Color(hex: "#3366FF"))
                            .cornerRadius(8)
                    }
                }
            }

            if let err = errorMessage, !err.isEmpty {
                Text("⚠️ \(err)")
                    .font(.caption)
                    .foregroundColor(Color(hex: "#FF6644"))
                    .padding(.top, 8)
                    .padding(.leading, 50)
            }
        }
        .padding(14)
        .background(Color(hex: "#141422"))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(status == .granted ? Color(hex: "#44FF88").opacity(0.2) : Color(white: 0.1), lineWidth: 1)
        )
    }
}

enum PermissionStatus { case granted, pending, denied }

@MainActor
final class PermissionsViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {

    @Published var notificationsStatus: PermissionStatus = .pending
    @Published var locationStatus: PermissionStatus = .pending
    @Published var locationBgStatus: PermissionStatus = .pending
    @Published var screenTimeStatus: PermissionStatus = .pending
    @Published var backgroundRefreshStatus: PermissionStatus = .pending
    @Published var screenTimeError: String = ""

    /// Quando true, ao receber a mudança de autorização "When In Use" via
    /// delegate, solicitamos automaticamente o upgrade para "Always" — usado
    /// pelo fluxo de Localização em Background, que precisa das duas etapas
    /// em sequência sem depender de tempo fixo (asyncAfter).
    private var pendingAlwaysUpgrade = false

    private let locationManager = CLLocationManager()

    override init() {
        super.init()
        locationManager.delegate = self
    }

    func checkAll() {
        checkNotifications()
        checkLocation()
        checkScreenTime()
        checkBackgroundRefresh()
    }

    private func checkNotifications() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let isGranted = settings.authorizationStatus == .authorized
            DispatchQueue.main.async {
                self.notificationsStatus = isGranted ? .granted : .pending
            }
        }
    }

    private func checkLocation() {
        let status = locationManager.authorizationStatus
        locationStatus   = (status == .authorizedWhenInUse || status == .authorizedAlways) ? .granted : .pending
        locationBgStatus = status == .authorizedAlways ? .granted : .pending
    }

    private func checkScreenTime() {
        #if !targetEnvironment(simulator)
        let authStatus = AuthorizationCenter.shared.authorizationStatus
        screenTimeStatus = authStatus == .approved ? .granted : .pending
        #else
        screenTimeStatus = .pending
        #endif
    }

    private func checkBackgroundRefresh() {
        let status = UIApplication.shared.backgroundRefreshStatus
        backgroundRefreshStatus = status == .available ? .granted : .pending
    }

    func requestNotifications() async {
        let granted = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge, .sound])
        notificationsStatus = (granted == true) ? .granted : .denied
    }

    func requestLocation() {
        pendingAlwaysUpgrade = false
        locationManager.requestWhenInUseAuthorization()
        // O resultado chega via locationManagerDidChangeAuthorization(_:)
        // abaixo — sem depender de tempo fixo, evitando estado inconsistente.
    }

    func requestLocationAlways() {
        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            // Ainda não pediu nada — primeiro pede o "When In Use" (passo
            // obrigatório do iOS antes de poder solicitar "Always"). O
            // upgrade automático para "Always" acontece no callback do
            // delegate, quando o "When In Use" for de fato concedido.
            pendingAlwaysUpgrade = true
            locationManager.requestWhenInUseAuthorization()
        } else if status == .authorizedWhenInUse {
            // iOS só mostra o diálogo de upgrade para "Always" quando já há
            // "When In Use" concedido.
            pendingAlwaysUpgrade = false
            locationManager.requestAlwaysAuthorization()
        } else {
            // Já negado ou em estado que exige ajuste manual.
            pendingAlwaysUpgrade = false
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Callback oficial da Apple para mudanças de autorização — chamado
        // de forma confiável tanto na primeira concessão/negação quanto em
        // qualquer alteração feita depois nas Configurações do iPhone.
        // CLAuthorizationStatus é um enum simples (Sendable), então é
        // seguro extraí-lo aqui fora e só então saltar para o MainActor.
        let newStatus = manager.authorizationStatus
        Task { @MainActor [weak self] in
            self?.handleAuthorizationChange(newStatus)
        }
    }

    @MainActor
    private func handleAuthorizationChange(_ status: CLAuthorizationStatus) {
        checkLocation()
        if pendingAlwaysUpgrade && status == .authorizedWhenInUse {
            pendingAlwaysUpgrade = false
            locationManager.requestAlwaysAuthorization()
        }
    }

    func requestScreenTime() async {
        #if !targetEnvironment(simulator)
        screenTimeError = ""
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            ScreenTimeManager.shared.isAuthorized = true
            screenTimeStatus = .granted
        } catch {
            screenTimeError = error.localizedDescription
            screenTimeStatus = .denied
        }
        #endif
    }
}
