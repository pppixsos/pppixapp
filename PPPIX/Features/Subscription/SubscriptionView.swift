import SwiftUI
import StoreKit

// MARK: - SubscriptionView

struct SubscriptionView: View {

    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = StoreManager.shared
    @State private var selectedPlan: String? = "tech.pppix.app.premium_anual"
    @State private var isPurchasing = false
    @State private var errorMessage = ""
    @State private var successMessage = ""
    @State private var showPrivacy = false
    @State private var showTerms = false
    @State private var shimmer = false

    // MARK: - Layout

    var body: some View {
        ZStack {
            // Background
            backgroundLayer

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    closeButton
                    headerSection
                    featuresSection
                    trialBadge
                    plansSection
                    ctaSection
                    legalSection
                }
                .padding(.bottom, 40)
            }

            // Toast
            if !successMessage.isEmpty || !errorMessage.isEmpty {
                toastOverlay
            }
        }
        .ignoresSafeArea()
        .task { await store.loadProducts() }
        .sheet(isPresented: $showPrivacy) {
            PolicyWebView(url: "https://privacidade.pppix.online/ios", title: "Política de Privacidade")
        }
        .sheet(isPresented: $showTerms) {
            PolicyWebView(url: "https://privacidade.pppix.online/ios", title: "Termos de Uso")
        }
    }

    // MARK: - Background

    private var backgroundLayer: some View {
        ZStack {
            Color(hex: "#08080F").ignoresSafeArea()
            // Ambient glow top
            RadialGradient(
                colors: [Color(hex: "#1A2E6E").opacity(0.6), .clear],
                center: .init(x: 0.5, y: 0.0),
                startRadius: 0, endRadius: 320
            )
            .ignoresSafeArea()
            // Ambient glow bottom
            RadialGradient(
                colors: [Color(hex: "#0D3D2A").opacity(0.4), .clear],
                center: .init(x: 0.5, y: 1.0),
                startRadius: 0, endRadius: 280
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Close Button

    private var closeButton: some View {
        HStack {
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(white: 0.5))
                    .frame(width: 32, height: 32)
                    .background(Color(white: 1).opacity(0.06))
                    .clipShape(Circle())
            }
            .padding(.trailing, 20)
            .padding(.top, 56)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 16) {
            // Icon badge
            ZStack {
                // Outer glow ring
                Circle()
                    .stroke(
                        LinearGradient(colors: [Color(hex: "#2B5BFF").opacity(0.4), Color(hex: "#00C77A").opacity(0.3)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1.5
                    )
                    .frame(width: 96, height: 96)

                Circle()
                    .fill(LinearGradient(
                        colors: [Color(hex: "#0F1A3A"), Color(hex: "#0A1428")],
                        startPoint: .top, endPoint: .bottom))
                    .frame(width: 88, height: 88)

                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(LinearGradient(
                        colors: [Color(hex: "#4D8FFF"), Color(hex: "#00C77A")],
                        startPoint: .top, endPoint: .bottom))
            }
            .shadow(color: Color(hex: "#2B5BFF").opacity(0.3), radius: 24)

            VStack(spacing: 8) {
                Text("PPPIX Premium")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("Proteção total para sua família")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color(white: 0.55))
            }

            // Stars / social proof
            HStack(spacing: 4) {
                ForEach(0..<5) { _ in
                    Image(systemName: "star.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#FFD700"))
                }
                Text("4.9 • Mais de 10 mil famílias protegidas")
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 0.45))
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 28)
    }

    // MARK: - Features

    private var featuresSection: some View {
        VStack(spacing: 0) {
            // Section header
            HStack {
                Text("O que você recebe")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(white: 0.4))
                    .textCase(.uppercase)
                    .tracking(1.2)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            // Features grid
            VStack(spacing: 2) {
                FeatureRow(
                    icon: "building.columns.fill",
                    iconColor: Color(hex: "#4D8FFF"),
                    title: "Bloqueio de apps bancários",
                    subtitle: "Impede acesso não autorizado a bancos e fintechs"
                )
                FeatureRow(
                    icon: "shield.lefthalf.filled.badge.checkmark",
                    iconColor: Color(hex: "#00C77A"),
                    title: "Proteção contra golpes digitais",
                    subtitle: "Filtra ameaças e fraudes em tempo real"
                )
                FeatureRow(
                    icon: "exclamationmark.shield.fill",
                    iconColor: Color(hex: "#FF6B35"),
                    title: "Alerta de emergência SOS",
                    subtitle: "Notificação imediata para todo o grupo familiar"
                )
                FeatureRow(
                    icon: "location.fill",
                    iconColor: Color(hex: "#4D8FFF"),
                    title: "Localização em emergências",
                    subtitle: "GPS preciso compartilhado no alerta de SOS"
                )
                FeatureRow(
                    icon: "car.fill",
                    iconColor: Color(hex: "#A78BFA"),
                    title: "Dados do veículo no alerta",
                    subtitle: "Placa, modelo e histórico enviados no SOS"
                )
                FeatureRow(
                    icon: "person.2.fill",
                    iconColor: Color(hex: "#00C77A"),
                    title: "Grupo familiar ilimitado",
                    subtitle: "Adicione toda a família sem restrição de membros"
                )
                FeatureRow(
                    icon: "hand.raised.slash.fill",
                    iconColor: Color(hex: "#FF6B35"),
                    title: "Bloqueio de conteúdo adulto",
                    subtitle: "Controle o que seus filhos acessam online"
                )
                FeatureRow(
                    icon: "creditcard.fill",
                    iconColor: Color(hex: "#FFD700"),
                    title: "Monitoramento financeiro",
                    subtitle: "Alerta quando apps de pagamento são abertos"
                )
            }
            .background(Color(white: 1).opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color(white: 1).opacity(0.07), lineWidth: 1)
            )
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Trial Badge

    private var trialBadge: some View {
        HStack(spacing: 10) {
            Image(systemName: "gift.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(LinearGradient(
                    colors: [Color(hex: "#00C77A"), Color(hex: "#00A86B")],
                    startPoint: .top, endPoint: .bottom))

            VStack(alignment: .leading, spacing: 2) {
                Text("3 dias completamente grátis")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(hex: "#00C77A"))
                Text("Sem cobrança agora • Cancele quando quiser")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "#00C77A").opacity(0.7))
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Color(hex: "#00C77A").opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(hex: "#00C77A").opacity(0.25), lineWidth: 1)
        )
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    // MARK: - Plans

    private var plansSection: some View {
        VStack(spacing: 10) {
            // Section header
            HStack {
                Text("Escolha seu plano")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(white: 0.4))
                    .textCase(.uppercase)
                    .tracking(1.2)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 4)

            if store.isLoading {
                ProgressView()
                    .tint(.white)
                    .padding(.vertical, 30)
            } else if !store.products.isEmpty {
                // StoreKit products
                ForEach(store.products.sorted { a, _ in a.id.contains("anual") }, id: \.id) { product in
                    PlanCard(
                        product: product,
                        isSelected: selectedPlan == product.id,
                        onTap: { selectedPlan = product.id }
                    )
                    .padding(.horizontal, 20)
                }
            } else {
                // Fallback manual
                PlanCardFallback(
                    id: "tech.pppix.app.premium_anual",
                    title: "Anual",
                    price: "R$ 129,90/ano",
                    detail: "Equivale a R$ 10,83/mês",
                    badge: "Economize 22%",
                    isHighlighted: true,
                    isSelected: selectedPlan == "tech.pppix.app.premium_anual",
                    onTap: { selectedPlan = "tech.pppix.app.premium_anual" }
                )
                .padding(.horizontal, 20)

                PlanCardFallback(
                    id: "tech.pppix.app.premium_mensal",
                    title: "Mensal",
                    price: "R$ 13,90/mês",
                    detail: "Flexibilidade total",
                    badge: nil,
                    isHighlighted: false,
                    isSelected: selectedPlan == "tech.pppix.app.premium_mensal",
                    onTap: { selectedPlan = "tech.pppix.app.premium_mensal" }
                )
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - CTA

    private var ctaSection: some View {
        VStack(spacing: 12) {
            // Main CTA
            Button {
                Task { await purchaseSelected() }
            } label: {
                ZStack {
                    if isPurchasing {
                        ProgressView().tint(.white)
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 16))
                            Text("Começar 3 dias grátis")
                                .font(.system(size: 17, weight: .bold))
                        }
                        .foregroundColor(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    LinearGradient(
                        colors: [Color(hex: "#2B5BFF"), Color(hex: "#1A3BCC")],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: Color(hex: "#2B5BFF").opacity(0.4), radius: 16, y: 6)
            }
            .disabled(isPurchasing || selectedPlan == nil)
            .padding(.horizontal, 20)
            .padding(.top, 20)

            // Restore
            Button {
                Task { await restorePurchases() }
            } label: {
                Text("Restaurar compras anteriores")
                    .font(.system(size: 13))
                    .foregroundColor(Color(white: 0.45))
                    .underline()
            }
        }
    }

    // MARK: - Legal

    private var legalSection: some View {
        VStack(spacing: 10) {
            // Divider
            Rectangle()
                .fill(Color(white: 1).opacity(0.06))
                .frame(height: 1)
                .padding(.horizontal, 20)
                .padding(.top, 16)

            Text("A assinatura será cobrada automaticamente ao final do período gratuito. Você pode cancelar a qualquer momento nas configurações da sua conta Apple. A renovação é automática salvo cancelamento com pelo menos 24 horas de antecedência.")
                .font(.system(size: 11))
                .foregroundColor(Color(white: 0.3))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            HStack(spacing: 8) {
                Button("Política de Privacidade") { showPrivacy = true }
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 0.4))

                Text("•")
                    .foregroundColor(Color(white: 0.2))

                Button("Termos de Uso") { showTerms = true }
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 0.4))
            }

            Text("© 2026 PPPIX Tecnologia Ltda")
                .font(.system(size: 11))
                .foregroundColor(Color(white: 0.2))
        }
        .padding(.top, 8)
    }

    // MARK: - Toast

    private var toastOverlay: some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                Image(systemName: successMessage.isEmpty ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundColor(successMessage.isEmpty ? Color(hex: "#FF6B35") : Color(hex: "#00C77A"))
                Text(successMessage.isEmpty ? errorMessage : successMessage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(hex: "#1A1A2E").opacity(0.97))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.4), radius: 20)
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    successMessage = ""; errorMessage = ""
                }
            }
        }
    }

    // MARK: - Actions

    private func purchaseSelected() async {
        guard let id = selectedPlan else { return }

        if let product = store.products.first(where: { $0.id == id }) {
            isPurchasing = true; errorMessage = ""
            do {
                let result = try await product.purchase()
                switch result {
                case .success(let verification):
                    switch verification {
                    case .verified(let tx):
                        await tx.finish()
                        store.isPremium = true
                        AdManager.shared.setPremium(true)
                        successMessage = "🎉 Bem-vindo ao PPPIX Premium!"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { dismiss() }
                    case .unverified:
                        errorMessage = "Compra não verificada. Tente restaurar compras."
                    }
                case .userCancelled: break
                case .pending:
                    errorMessage = "Compra pendente. Aguarde confirmação da Apple."
                @unknown default: break
                }
            } catch {
                errorMessage = "Erro ao processar compra. Tente novamente."
            }
            isPurchasing = false
        } else {
            // Fallback: abrir App Store
            if let url = URL(string: "https://apps.apple.com/app/id6773364223") {
                await UIApplication.shared.open(url)
            }
        }
    }

    private func restorePurchases() async {
        do {
            try await AppStore.sync()
            await store.checkPremiumStatus()
            if store.isPremium {
                successMessage = "✓ Assinatura restaurada com sucesso!"
                AdManager.shared.setPremium(true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { dismiss() }
            } else {
                errorMessage = "Nenhuma assinatura ativa encontrada."
            }
        } catch {
            errorMessage = "Erro ao restaurar. Verifique sua conexão."
        }
    }
}

// MARK: - FeatureRow

private struct FeatureRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 0.45))
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Color(hex: "#00C77A"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.clear)
    }
}

// MARK: - PlanCard (StoreKit)

private struct PlanCard: View {
    let product: Product
    let isSelected: Bool
    let onTap: () -> Void

    var isAnnual: Bool { product.id.contains("anual") || product.id.contains("annual") }

    var monthlyEquivalent: String {
        guard isAnnual, let price = product.price as Decimal? else { return "" }
        let monthly = price / 12
        return String(format: "Equivale a R$ %.2f/mês", NSDecimalNumber(decimal: monthly).doubleValue)
    }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                HStack(spacing: 14) {
                    // Radio
                    ZStack {
                        Circle()
                            .stroke(isSelected ? Color(hex: "#2B5BFF") : Color(white: 0.2), lineWidth: 2)
                            .frame(width: 22, height: 22)
                        if isSelected {
                            Circle()
                                .fill(Color(hex: "#2B5BFF"))
                                .frame(width: 12, height: 12)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(isAnnual ? "Anual" : "Mensal")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)

                        Text(product.displayPrice + (isAnnual ? "/ano" : "/mês"))
                            .font(.system(size: 14))
                            .foregroundColor(Color(white: 0.6))

                        if isAnnual {
                            Text(monthlyEquivalent + " • 3 dias grátis")
                                .font(.system(size: 12))
                                .foregroundColor(Color(hex: "#00C77A"))
                        } else {
                            Text("3 dias grátis inclusos")
                                .font(.system(size: 12))
                                .foregroundColor(Color(hex: "#00C77A"))
                        }
                    }

                    Spacer()
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isSelected
                            ? Color(hex: "#0D1A40")
                            : Color(white: 1).opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            isSelected
                                ? Color(hex: "#2B5BFF").opacity(0.7)
                                : Color(white: 1).opacity(0.08),
                            lineWidth: isSelected ? 1.5 : 1
                        )
                )

                // Popular badge
                if isAnnual {
                    Text("MAIS POPULAR")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .tracking(0.8)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: "#00C77A"), Color(hex: "#009E60")],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                        .offset(x: -12, y: -8)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - PlanCard Fallback

private struct PlanCardFallback: View {
    let id: String
    let title: String
    let price: String
    let detail: String
    let badge: String?
    let isHighlighted: Bool
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .stroke(isSelected ? Color(hex: "#2B5BFF") : Color(white: 0.2), lineWidth: 2)
                            .frame(width: 22, height: 22)
                        if isSelected {
                            Circle()
                                .fill(Color(hex: "#2B5BFF"))
                                .frame(width: 12, height: 12)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                        Text(price)
                            .font(.system(size: 14))
                            .foregroundColor(Color(white: 0.6))
                        Text(detail + " • 3 dias grátis")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "#00C77A"))
                    }

                    Spacer()
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isSelected ? Color(hex: "#0D1A40") : Color(white: 1).opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            isSelected ? Color(hex: "#2B5BFF").opacity(0.7) : Color(white: 1).opacity(0.08),
                            lineWidth: isSelected ? 1.5 : 1
                        )
                )

                if let badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .tracking(0.8)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(LinearGradient(
                            colors: [Color(hex: "#00C77A"), Color(hex: "#009E60")],
                            startPoint: .leading, endPoint: .trailing))
                        .clipShape(Capsule())
                        .offset(x: -12, y: -8)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - PolicyWebView

struct PolicyWebView: View {
    let url: String
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#08080F").ignoresSafeArea()
                VStack(spacing: 20) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 48))
                        .foregroundColor(Color(hex: "#2B5BFF"))
                    Text(title)
                        .font(.title2.bold())
                        .foregroundColor(.white)
                    Text("Acesse em:\n\(url)")
                        .font(.subheadline)
                        .foregroundColor(Color(white: 0.5))
                        .multilineTextAlignment(.center)
                    Button("Abrir no Safari") {
                        if let u = URL(string: url) { UIApplication.shared.open(u) }
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(Color(hex: "#2B5BFF"))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(32)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fechar") { dismiss() }.foregroundColor(Color(hex: "#2B5BFF"))
                }
            }
        }
    }
}

// MARK: - StoreManager

@MainActor
final class StoreManager: ObservableObject {
    static let shared = StoreManager()
    private init() {}

    private let productIds = [
        "tech.pppix.app.premium_mensal",
        "tech.pppix.app.premium_anual"
    ]

    @Published var products: [Product] = []
    @Published var isLoading = false

    // isPremium persiste no UserDefaults — não some ao fechar o app
    @Published var isPremium: Bool = UserDefaults.standard.bool(forKey: "pppix_is_premium") {
        didSet { UserDefaults.standard.set(isPremium, forKey: "pppix_is_premium") }
    }

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        products = (try? await Product.products(for: productIds))?.sorted {
            $0.id.contains("anual") && !$1.id.contains("anual")
        } ?? []
        await checkPremiumStatus()
    }

    func checkPremiumStatus() async {
        var found = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let tx) = result,
               productIds.contains(tx.productID) {
                isPremium = true
                AdManager.shared.setPremium(true)
                found = true
                return
            }
        }
        // Se StoreKit não confirmou nenhuma assinatura ativa, resetar
        if !found && isPremium {
            isPremium = false
            AdManager.shared.setPremium(false)
        }
    }

    // Listener de renovações automáticas — chamar no app init
    func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            for await result in Transaction.updates {
                if case .verified(let tx) = result {
                    await MainActor.run {
                        if self.productIds.contains(tx.productID) {
                            self.isPremium = true
                            AdManager.shared.setPremium(true)
                        }
                    }
                    await tx.finish()
                }
            }
        }
    }
}

// MARK: - AdManager

@MainActor
final class AdManager {
    static let shared = AdManager()
    private init() {}
    var isPremium: Bool { UserDefaults.standard.bool(forKey: "pppix_is_premium") }
    func setPremium(_ v: Bool) { UserDefaults.standard.set(v, forKey: "pppix_is_premium") }
}
