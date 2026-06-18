import SwiftUI
import CoreLocation
import UserNotifications
#if !targetEnvironment(simulator)
import FamilyControls
#endif

/// Lista de permissões apresentadas uma a uma durante o onboarding,
/// reaproveitando o PermissionsViewModel já existente no app (mesma
/// lógica usada na tela de Permissões acessível pela Home).
struct OnboardingPermissionsStep: View {
    let onNext: () -> Void

    @StateObject private var viewModel = PermissionsViewModel()
    @State private var currentIndex = 0
    @State private var hasInteracted: Set<Int> = []

    private struct Item {
        let icon: String
        let color: Color
        let title: String
        let description: String
        let status: PermissionStatus
        let errorMessage: String
        let actionLabel: String
        let hint: String?
        let onGrant: () -> Void
    }

    private var items: [Item] {
        var list: [Item] = [
            Item(icon: "bell.badge.fill", color: Color(hex: "#FF6600"),
                 title: "Notificações", description: "Para receber alertas de emergência dos seus contatos.",
                 status: viewModel.notificationsStatus, errorMessage: "", actionLabel: "Continuar", hint: nil,
                 onGrant: { Task { await viewModel.requestNotifications() } }),
            Item(icon: "location.fill", color: Color(hex: "#3366FF"),
                 title: "Localização", description: "Envia sua posição GPS no alerta de emergência.",
                 status: viewModel.locationStatus, errorMessage: "", actionLabel: "Continuar",
                 hint: "Um aviso do iOS vai aparecer no topo da tela — escolha sua preferência nele.",
                 onGrant: { viewModel.requestLocation() }),
            Item(icon: "location.fill.viewfinder", color: Color(hex: "#0099FF"),
                 title: "Localização em Background", description: "Permite enviar posição mesmo com a tela bloqueada.",
                 status: viewModel.locationBgStatus, errorMessage: "", actionLabel: "Continuar",
                 hint: "Se nada aparecer, toque novamente — o iOS às vezes pede em duas etapas.",
                 onGrant: { viewModel.requestLocationAlways() }),
        ]
        #if !targetEnvironment(simulator)
        list.append(Item(icon: "hourglass", color: Color(hex: "#6633FF"),
             title: "Screen Time", description: "Necessário para bloquear apps financeiros com senha.",
             status: viewModel.screenTimeStatus, errorMessage: viewModel.screenTimeError, actionLabel: "Continuar", hint: nil,
             onGrant: { Task { await viewModel.requestScreenTime() } }))
        #endif
        list.append(Item(icon: "arrow.clockwise.circle.fill", color: Color(hex: "#FF9900"),
             title: "Atualização em Segundo Plano", description: "Mantém o app funcionando mesmo fechado.",
             status: viewModel.backgroundRefreshStatus, errorMessage: "", actionLabel: "Ir para Ajustes",
             hint: "Você será levado às Configurações do iPhone. Ative e volte para o app.",
             onGrant: {
                 if let url = URL(string: UIApplication.openSettingsURLString) {
                     UIApplication.shared.open(url)
                 }
             }))
        return list
    }

    var body: some View {
        let item = items[min(currentIndex, items.count - 1)]

        OnboardingStepShell(
            icon: item.icon,
            iconColor: item.color,
            title: item.title,
            subtitle: item.description,
            stepIndex: 4,
            totalSteps: 13
        ) {
            VStack(spacing: 18) {
                if item.status == .granted {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(Color(hex: "#44FF88"))
                        Text("Permissão concedida").foregroundColor(Color(hex: "#44FF88"))
                    }
                    .font(.subheadline.bold())
                    .padding(.vertical, 14)
                } else {
                    PPPIXButton(title: item.actionLabel) {
                        hasInteracted.insert(currentIndex)
                        item.onGrant()
                    }

                    if let hint = item.hint {
                        Text(hint)
                            .font(.caption)
                            .foregroundColor(Color(white: 0.45))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    }

                    if !item.errorMessage.isEmpty {
                        ErrorBanner(message: item.errorMessage)
                    }
                }

                // O avanço só fica disponível depois que o usuário já
                // interagiu com o pedido (concedido OU já tocou no botão
                // que aciona o diálogo nativo do iOS) — nunca antes disso,
                // conforme exigido pela Apple (Guideline 5.1.1).
                if item.status == .granted || hasInteracted.contains(currentIndex) {
                    Button(item.status == .granted ? "Continuar" : "Próximo") {
                        advance()
                    }
                    .font(.subheadline.weight(item.status == .granted ? .bold : .medium))
                    .foregroundColor(item.status == .granted ? .white : Color(white: 0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, item.status == .granted ? 14 : 10)
                    .background(item.status == .granted ? Color(hex: "#3366FF") : Color.clear)
                    .cornerRadius(12)
                }

                Text("\(currentIndex + 1) de \(items.count)")
                    .font(.caption)
                    .foregroundColor(Color(white: 0.4))
            }
        }
        .onAppear { viewModel.checkAll() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // Usuário pode ter ido nas Configurações do iOS e voltado —
            // reavalia o status real de cada permissão.
            viewModel.checkAll()
        }
    }

    private func advance() {
        guard currentIndex < items.count else { return }
        if currentIndex < items.count - 1 {
            currentIndex += 1
        } else {
            SessionManager.shared.werePermissionsAsked = true
            onNext()
        }
    }
}
