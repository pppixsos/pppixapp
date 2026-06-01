import SwiftUI
import StoreKit

struct SubscriptionView: View {

    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = StoreManager.shared
    @State private var isPurchasing = false
    @State private var selectedPlan: String? = nil
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
                            ZStack {
                                Circle()
                                    .fill(LinearGradient(
                                        colors: [Color(hex: "#3366FF").opacity(0.2), Color(hex: "#6633FF").opacity(0.1)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 88, height: 88)
                                Image(systemName: "shield.fill")
                                    .font(.system(size: 40))
                                    .foregroundStyle(LinearGradient(
                                        colors: [Color(hex: "#3366FF"), Color(hex: "#6633FF")],
                                        startPoint: .top, endPoint: .bottom))
                            }
                            Text("PPPIX Premium")
                                .font(.title.bold()).foregroundColor(.white)
                            Text("3 dias grátis, depois escolha seu plano")
                                .font(.subheadline).foregroundColor(Color(white: 0.6))
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 20)

                        // Benefícios
                        PPPIXCard {
                            VStack(alignment: .leading, spacing: 14) {
                                BenefitRow(icon: "lock.shield.fill",  text: "Bloqueio de apps bancários")
                                BenefitRow(icon: "bell.badge.fill",   text: "Alertas de emergência em tempo real")
                                BenefitRow(icon: "location.fill",     text: "Localização no alerta de emergência")
                                BenefitRow(icon: "car.fill",          text: "Dados do veículo no alerta")
                                BenefitRow(icon: "person.2.fill",     text: "Grupo de emergência ilimitado")
                            }
                        }

                        // Badge 3 dias grátis
                        HStack(spacing: 8) {
                            Image(systemName: "gift.fill")
                                .foregroundColor(Color(hex: "#44FF88"))
                            Text("3 dias grátis • Cancele quando quiser")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Color(hex: "#44FF88"))
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Color(hex: "#44FF88").opacity(0.1))
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(hex: "#44FF88").opacity(0.3), lineWidth: 1))

                        // Planos
                        if store.isLoading {
                            ProgressView().tint(Color(hex: "#3366FF")).padding(.vertical, 20)
                        } else if store.products.isEmpty {
                            // Fallback se StoreKit não carregou
                            VStack(spacing: 12) {
                                PlanCardFallback(
                                    title: "Plano Mensal",
                                    price: "R$ 9,90/mês",
                                    badge: nil,
                                    isSelected: selectedPlan == "mensal",
                                    onTap: { selectedPlan = "mensal" }
                                )
                                PlanCardFallback(
                                    title: "Plano Anual",
                                    price: "R$ 97,90/ano",
                                    badge: "Economize 17%",
                                    isSelected: selectedPlan == "anual",
                                    onTap: { selectedPlan = "anual" }
                                )
                            }
                        } else {
                            VStack(spacing: 12) {
                                ForEach(store.products.sorted { a, _ in
                                    a.id.contains("mensal") || a.id.contains("monthly")
                                }, id: \.id) { product in
                                    PlanCard(
                                        product: product,
                                        isSelected: selectedPlan == product.id,
                                        onTap: { selectedPlan = product.id }
                                    )
                                }
                            }
                        }

                        if !errorMessage.isEmpty { ErrorBanner(message: errorMessage) }
                        if !successMessage.isEmpty {
                            Text(successMessage).font(.footnote)
                                .foregroundColor(Color(hex: "#44FF88"))
                                .multilineTextAlignment(.center)
                        }

                        // Botão assinar
                        PPPIXButton(
                            title: isPurchasing ? "Processando..." : "Começar 3 dias grátis",
                            isLoading: isPurchasing
                        ) {
                            Task { await purchaseSelected() }
                        }

                        // Restaurar
                        Button("Restaurar Compras") { Task { await restorePurchases() } }
                            .font(.footnote).foregroundColor(Color(white: 0.4))

                        Text("Após o período gratuito, a assinatura é renovada automaticamente. Cancele a qualquer momento em Ajustes > Apple ID > Assinaturas.")
                            .font(.caption2).foregroundColor(Color(white: 0.3))
                            .multilineTextAlignment(.center).padding(.horizontal, 8)

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
                        Image(systemName: "xmark.circle.fill").foregroundColor(Color(white: 0.4))
                    }
                }
            }
        }
        .task {
            await store.loadProducts()
            // Pré-selecionar plano anual
            if let anual = store.products.first(where: { $0.id.contains("anual") || $0.id.contains("annual") }) {
                selectedPlan = anual.id
            } else {
                selectedPlan = store.products.first?.id
            }
        }
    }

    private func purchaseSelected() async {
        guard let id = selectedPlan,
              let product = store.products.first(where: { $0.id == id }) else {
            // Fallback: abrir App Store
            if let url = URL(string: "https://apps.apple.com/app/id6773364223") {
                await UIApplication.shared.open(url)
            }
            return
        }
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
                errorMessage = "Compra pendente. Aguarde a confirmação da Apple."
            @unknown default: break
            }
        } catch {
            errorMessage = "Erro ao processar compra. Tente novamente."
        }
        isPurchasing = false
    }

    private func restorePurchases() async {
        do {
            try await AppStore.sync()
            await store.checkPremiumStatus()
            if store.isPremium {
                successMessage = "✓ Assinatura restaurada!"
                AdManager.shared.setPremium(true)
            } else {
                errorMessage = "Nenhuma assinatura ativa encontrada."
            }
        } catch {
            errorMessage = "Erro ao restaurar. Verifique sua conexão."
        }
    }
}

// MARK: - PlanCard (StoreKit)

private struct PlanCard: View {
    let product: Product
    let isSelected: Bool
    let onTap: () -> Void

    var isMonthly: Bool { product.id.contains("mensal") || product.id.contains("monthly") }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Radio
                Circle()
                    .stroke(isSelected ? Color(hex: "#3366FF") : Color(white: 0.3), lineWidth: 2)
                    .frame(width: 20, height: 20)
                    .overlay(isSelected ?
                        Circle().fill(Color(hex: "#3366FF")).frame(width: 12) : nil)

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(isMonthly ? "Mensal" : "Anual")
                            .font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                        if !isMonthly {
                            Text("Economize 17%")
                                .font(.caption2.bold()).foregroundColor(.white)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Color(hex: "#44FF88")).cornerRadius(6)
                        }
                    }
                    Text(product.displayPrice + (isMonthly ? "/mês" : "/ano"))
                        .font(.subheadline).foregroundColor(Color(white: 0.65))
                    if isMonthly {
                        Text("3 dias grátis")
                            .font(.caption).foregroundColor(Color(hex: "#44FF88"))
                    } else {
                        Text("Equivale a R$ 8,16/mês • 3 dias grátis")
                            .font(.caption).foregroundColor(Color(hex: "#44FF88"))
                    }
                }
                Spacer()
            }
            .padding(16)
            .background(Color(hex: isSelected ? "#1A2440" : "#141422"))
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? Color(hex: "#3366FF").opacity(0.6) : Color(white: 0.1), lineWidth: isSelected ? 1.5 : 1))
        }
    }
}

// MARK: - PlanCard Fallback (sem StoreKit)

private struct PlanCardFallback: View {
    let title: String
    let price: String
    let badge: String?
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Circle()
                    .stroke(isSelected ? Color(hex: "#3366FF") : Color(white: 0.3), lineWidth: 2)
                    .frame(width: 20, height: 20)
                    .overlay(isSelected ?
                        Circle().fill(Color(hex: "#3366FF")).frame(width: 12) : nil)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(title).font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                        if let badge {
                            Text(badge).font(.caption2.bold()).foregroundColor(.white)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Color(hex: "#44FF88")).cornerRadius(6)
                        }
                    }
                    Text(price).font(.subheadline).foregroundColor(Color(white: 0.65))
                    Text("3 dias grátis").font(.caption).foregroundColor(Color(hex: "#44FF88"))
                }
                Spacer()
            }
            .padding(16)
            .background(Color(hex: isSelected ? "#1A2440" : "#141422"))
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? Color(hex: "#3366FF").opacity(0.6) : Color(white: 0.1), lineWidth: isSelected ? 1.5 : 1))
        }
    }
}

private struct BenefitRow: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundColor(Color(hex: "#3366FF"))
                .font(.system(size: 14)).frame(width: 20)
            Text(text).font(.subheadline).foregroundColor(.white)
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
            if case .verified(let tx) = result,
               productIds.contains(tx.productID) {
                isPremium = true
                AdManager.shared.setPremium(true)
                return
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
