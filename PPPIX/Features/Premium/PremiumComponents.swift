import SwiftUI
import StoreKit

// MARK: - Banner Premium contextual

struct PremiumBanner: View {
    let message: String
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button { onTap?() } label: {
            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 13))
                    .foregroundColor(Color(white: 0.4))
                VStack(alignment: .leading, spacing: 2) {
                    Text(message)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(white: 0.5))
                        .multilineTextAlignment(.leading)
                    Text("Assinar Premium →")
                        .font(.caption.bold())
                        .foregroundColor(Color(hex: "#3366FF"))
                }
                Spacer()
            }
            .padding(14)
            .background(Color(white: 0.06))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(white: 0.1), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Paywall

struct PremiumPaywallView: View {
    let onClose: () -> Void

    @ObservedObject private var premium = PremiumManager.shared
    @State private var selectedPlan: PlanType = .yearly
    @State private var showTerms = false
    @State private var showPrivacy = false
    @State private var showError = false

    enum PlanType { case monthly, yearly }

    private let benefits: [(icon: String, color: String, title: String, subtitle: String)] = [
        ("person.3.fill",         "#3366FF", "Contatos ilimitados",       "Adicione quantos contatos quiser"),
        ("car.2.fill",            "#FF6600", "Veículos ilimitados",        "Cadastre todos os seus veículos"),
        ("apps.iphone.badge.plus","#6633FF", "Apps ilimitados protegidos", "Bloqueie quantos apps precisar"),
        ("message.badge.filled.fill","#25D366","Disparo via WhatsApp",     "Alertas chegam em qualquer celular"),
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()

            VStack(spacing: 0) {
                // Puxador
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(white: 0.3))
                    .frame(width: 40, height: 5)
                    .padding(.top, 12)
                    .padding(.bottom, 4)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {

                        // Header com gradiente
                        ZStack(alignment: .topTrailing) {
                            LinearGradient(
                                colors: [Color(hex: "#1A1040"), Color(hex: "#0A0A12")],
                                startPoint: .top, endPoint: .bottom
                            )
                            .frame(height: 160)

                            Button { onClose() } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(Color(white: 0.6))
                                    .frame(width: 30, height: 30)
                                    .background(Color(white: 0.15))
                                    .clipShape(Circle())
                            }
                            .padding(16)

                            VStack(spacing: 8) {
                                // Ícone com brilho
                                ZStack {
                                    Circle()
                                        .fill(
                                            RadialGradient(
                                                colors: [Color(hex: "#FFD700").opacity(0.3), .clear],
                                                center: .center, startRadius: 0, endRadius: 36
                                            )
                                        )
                                        .frame(width: 72, height: 72)
                                    Image(systemName: "crown.fill")
                                        .font(.system(size: 34))
                                        .foregroundStyle(
                                            LinearGradient(
                                                colors: [Color(hex: "#FFE066"), Color(hex: "#FFB700")],
                                                startPoint: .top, endPoint: .bottom
                                            )
                                        )
                                }

                                Text("PPPIX Premium")
                                    .font(.title2.bold())
                                    .foregroundColor(.white)

                                Text("Proteção completa, sem limites")
                                    .font(.subheadline)
                                    .foregroundColor(Color(white: 0.55))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 20)
                        }

                        // Benefícios
                        VStack(spacing: 10) {
                            ForEach(benefits, id: \.title) { b in
                                HStack(spacing: 14) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(Color(hex: b.color).opacity(0.15))
                                            .frame(width: 42, height: 42)
                                        Image(systemName: b.icon)
                                            .font(.system(size: 18))
                                            .foregroundColor(Color(hex: b.color))
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(b.title)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(.white)
                                        Text(b.subtitle)
                                            .font(.caption)
                                            .foregroundColor(Color(white: 0.5))
                                    }
                                    Spacer()
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(Color(hex: "#44DD88"))
                                        .font(.system(size: 18))
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(Color(white: 0.06))
                                .cornerRadius(14)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 20)

                        // Seletor de planos
                        VStack(spacing: 10) {
                            // Anual
                            planCard(
                                type: .yearly,
                                title: "Anual",
                                badge: "MELHOR VALOR",
                                price: premium.yearlyProduct?.displayPrice ?? PremiumManager.yearlyPrice,
                                subtitle: "equivale a \(formatMonthly())/mês",
                                isSelected: selectedPlan == .yearly
                            )

                            // Mensal
                            planCard(
                                type: .monthly,
                                title: "Mensal",
                                badge: nil,
                                price: premium.monthlyProduct?.displayPrice ?? PremiumManager.monthlyPrice,
                                subtitle: "cobrado mensalmente",
                                isSelected: selectedPlan == .monthly
                            )
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 20)

                        // Erro
                        if let err = premium.purchaseError {
                            Text(err)
                                .font(.caption)
                                .foregroundColor(Color(hex: "#FF4444"))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                                .padding(.top, 8)
                        }

                        // Botão CTA
                        Button {
                            Task { await buySelected() }
                        } label: {
                            HStack(spacing: 10) {
                                if premium.isPurchasing {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.9)
                                } else {
                                    Image(systemName: "crown.fill")
                                        .font(.system(size: 16))
                                }
                                Text(premium.isPurchasing ? "Processando..." : "Assinar agora")
                                    .font(.system(size: 17, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                LinearGradient(
                                    colors: [Color(hex: "#4477FF"), Color(hex: "#7744FF")],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                            .cornerRadius(16)
                            .shadow(color: Color(hex: "#3366FF").opacity(0.5), radius: 12, x: 0, y: 6)
                        }
                        .disabled(premium.isPurchasing)
                        .padding(.horizontal, 16)
                        .padding(.top, 20)

                        // Footer
                        HStack(spacing: 16) {
                            Button("Restaurar compras") {
                                Task { await premium.restorePurchases() }
                            }
                            .font(.caption)
                            .foregroundColor(Color(white: 0.4))

                            Text("·").foregroundColor(Color(white: 0.2))

                            Button("Termos de Uso") { showTerms = true }
                                .font(.caption)
                                .foregroundColor(Color(white: 0.4))

                            Text("·").foregroundColor(Color(white: 0.2))

                            Button("Privacidade") { showPrivacy = true }
                                .font(.caption)
                                .foregroundColor(Color(white: 0.4))
                        }
                        .padding(.top, 12)

                        Text("Cancele quando quiser · Renovação automática")
                            .font(.caption2)
                            .foregroundColor(Color(white: 0.25))
                            .padding(.top, 6)
                            .padding(.bottom, 32)
                    }
                }
            }
            .background(Color(hex: "#0A0A12"))
            .cornerRadius(28)
            .padding(.horizontal, 8)
            .padding(.vertical, 60)
        }
        .task { await premium.loadProducts() }
        .onChange(of: premium.isPremium) { isPremium in
            if isPremium { onClose() }
        }
        .sheet(isPresented: $showTerms) {
            LegalDocumentView(title: "Termos de Uso", content: LegalDocument.termsOfUse)
        }
        .sheet(isPresented: $showPrivacy) {
            LegalDocumentView(title: "Política de Privacidade", content: LegalDocument.privacyPolicy)
        }
    }



    @State private var showTerms = false
    @State private var showPrivacy = false

    // MARK: - Plan card

    private func planCard(
        type: PlanType,
        title: String,
        badge: String?,
        price: String,
        subtitle: String,
        isSelected: Bool
    ) -> some View {
        Button { selectedPlan = type } label: {
            HStack(spacing: 14) {
                // Radio button
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color(hex: "#4477FF") : Color(white: 0.2), lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle()
                            .fill(Color(hex: "#4477FF"))
                            .frame(width: 12, height: 12)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                        if let badge {
                            Text(badge)
                                .font(.system(size: 10, weight: .black))
                                .foregroundColor(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(
                                    LinearGradient(
                                        colors: [Color(hex: "#4477FF"), Color(hex: "#7744FF")],
                                        startPoint: .leading, endPoint: .trailing
                                    )
                                )
                                .cornerRadius(5)
                        }
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(Color(white: 0.45))
                }

                Spacer()

                Text(price)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
            }
            .padding(16)
            .background(
                isSelected
                    ? Color(hex: "#4477FF").opacity(0.12)
                    : Color(white: 0.07)
            )
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isSelected ? Color(hex: "#4477FF").opacity(0.6) : Color(white: 0.1),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    // MARK: - Helpers

    private func buySelected() async {
        let product = selectedPlan == .yearly ? premium.yearlyProduct : premium.monthlyProduct
        guard let product else {
            premium.purchaseError = "Produto não disponível. Verifique sua conexão."
            return
        }
        await premium.purchase(product)
    }

    private func formatMonthly() -> String {
        guard let yearly = premium.yearlyProduct else { return "R$ 13,32" }
        let monthlyDecimal = yearly.price / 12
        // Usa o priceFormatStyle do produto para garantir a moeda correta
        // (real brasileiro quando o produto está configurado em BRL)
        return monthlyDecimal.formatted(yearly.priceFormatStyle)
    }
}
