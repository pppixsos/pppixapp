import SwiftUI
import StoreKit

struct SubscriptionView: View {

    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = StoreManager.shared
    @State private var isPurchasing = false
    @State private var errorMessage = ""
    @State private var successMessage = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#0A0A12").ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {

                        // Header
                        VStack(spacing: 12) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 52))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color(hex: "#FFD700"), Color(hex: "#FF9900")],
                                        startPoint: .top, endPoint: .bottom
                                    )
                                )
                            Text("PPPIX Premium")
                                .font(.title.bold())
                                .foregroundColor(.white)
                            Text("Suporte o desenvolvimento e remova os anúncios")
                                .font(.subheadline)
                                .foregroundColor(Color(white: 0.6))
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 20)

                        // Benefits
                        PPPIXCard {
                            VStack(alignment: .leading, spacing: 12) {
                                BenefitRow(icon: "nosign", text: "Sem anúncios")
                                BenefitRow(icon: "heart.fill", text: "Apoio ao desenvolvimento do PPPIX")
                                BenefitRow(icon: "bolt.fill", text: "Prioridade em novos recursos")
                                BenefitRow(icon: "person.fill.checkmark", text: "Badge Premium no perfil")
                            }
                        }

                        // Plans
                        if store.isLoading {
                            ProgressView().tint(Color(hex: "#FFD700"))
                        } else {
                            VStack(spacing: 12) {
                                ForEach(store.products, id: \.id) { product in
                                    PlanButton(
                                        product: product,
                                        isPurchasing: isPurchasing
                                    ) {
                                        Task { await purchase(product) }
                                    }
                                }
                            }
                        }

                        if !errorMessage.isEmpty {
                            ErrorBanner(message: errorMessage)
                        }
                        if !successMessage.isEmpty {
                            Text(successMessage)
                                .font(.footnote)
                                .foregroundColor(Color(hex: "#44FF88"))
                                .multilineTextAlignment(.center)
                        }

                        // Restore
                        Button("Restaurar Compras") {
                            Task { await restorePurchases() }
                        }
                        .font(.footnote)
                        .foregroundColor(Color(white: 0.5))

                        Text("As assinaturas são renovadas automaticamente. Cancele a qualquer momento no App Store > Assinaturas.")
                            .font(.caption2)
                            .foregroundColor(Color(white: 0.3))
                            .multilineTextAlignment(.center)

                        Spacer(minLength: 32)
                    }
                    .padding(.horizontal, 20)
                }
            }
            .navigationTitle("Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Color(white: 0.4))
                    }
                }
            }
        }
        .task { await store.loadProducts() }
    }

    private func purchase(_ product: Product) async {
        isPurchasing = true
        errorMessage = ""
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    store.isPremium = true
                    successMessage = "🎉 Bem-vindo ao Premium! Obrigado pelo apoio!"
                    AdManager.shared.setPremium(true)
                case .unverified:
                    errorMessage = "Compra não verificada. Entre em contato com o suporte."
                }
            case .userCancelled:
                break
            case .pending:
                errorMessage = "Compra pendente. Aguarde a confirmação."
            @unknown default:
                break
            }
        } catch {
            errorMessage = "Erro ao processar compra: \(error.localizedDescription)"
        }
        isPurchasing = false
    }

    private func restorePurchases() async {
        do {
            try await AppStore.sync()
            await store.checkPremiumStatus()
            if store.isPremium {
                successMessage = "✓ Compras restauradas com sucesso!"
            } else {
                errorMessage = "Nenhuma assinatura ativa encontrada."
            }
        } catch {
            errorMessage = "Erro ao restaurar compras."
        }
    }
}

// MARK: - PlanButton

private struct PlanButton: View {
    let product: Product
    let isPurchasing: Bool
    let onPurchase: () -> Void

    var isMonthly: Bool { product.id.contains("mensal") || product.id.contains("monthly") }

    var body: some View {
        Button(action: onPurchase) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isMonthly ? "Plano Mensal" : "Plano Anual")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    Text(product.displayPrice + (isMonthly ? "/mês" : "/ano"))
                        .font(.subheadline)
                        .foregroundColor(Color(white: 0.7))
                    if !isMonthly {
                        Text("Economize ~33% vs mensal")
                            .font(.caption)
                            .foregroundColor(Color(hex: "#44FF88"))
                    }
                }
                Spacer()
                if isPurchasing {
                    ProgressView().tint(.white)
                } else {
                    Text("Assinar")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(isMonthly ? Color(hex: "#3366FF") : Color(hex: "#FFD700"))
                        .cornerRadius(10)
                        .foregroundColor(isMonthly ? .white : .black)
                }
            }
            .padding(16)
            .background(Color(hex: "#1A1030"))
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isMonthly ? Color(hex: "#3366FF").opacity(0.4) : Color(hex: "#FFD700").opacity(0.4), lineWidth: 1)
            )
        }
        .disabled(isPurchasing)
    }
}

private struct BenefitRow: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(Color(hex: "#FFD700"))
                .font(.system(size: 14))
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.white)
        }
    }
}

// MARK: - StoreManager

@MainActor
final class StoreManager: ObservableObject {

    static let shared = StoreManager()
    private init() {}

    // Mesmo product ID do Android: "premium_mensal", planos "mensal" e "anual"
    private let productIds = ["tech.pppix.app.premium_mensal", "tech.pppix.app.premium_anual"]

    @Published var products: [Product] = []
    @Published var isPremium: Bool = false
    @Published var isLoading = false

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        products = (try? await Product.products(for: productIds)) ?? []
        await checkPremiumStatus()
    }

    func checkPremiumStatus() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if productIds.contains(transaction.productID) {
                    isPremium = true
                    AdManager.shared.setPremium(true)
                    return
                }
            }
        }
    }
}

// MARK: - AdManager

final class AdManager {
    static let shared = AdManager()
    private init() {}
    private let key = "pppix_is_premium"

    var isPremium: Bool { UserDefaults.standard.bool(forKey: key) }

    func setPremium(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
