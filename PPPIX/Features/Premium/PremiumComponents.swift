import SwiftUI

// MARK: - Banner Premium (contextual, aparece nas páginas com limite)

struct PremiumBanner: View {
    let message: String
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Color(white: 0.5))

                VStack(alignment: .leading, spacing: 2) {
                    Text(message)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(white: 0.55))
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
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(white: 0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Paywall View (popup comparativo Free vs Premium)

struct PremiumPaywallView: View {
    let onClose: () -> Void

    private let features: [(icon: String, text: String, free: Bool)] = [
        ("person.2.fill",        "1 contato de emergência",      true),
        ("person.3.fill",        "Contatos ilimitados",          false),
        ("car.fill",             "1 veículo cadastrado",         true),
        ("car.2.fill",           "Veículos ilimitados",          false),
        ("apps.iphone",          "1 app protegido",              true),
        ("apps.iphone.badge.plus","Apps ilimitados protegidos",  false),
        ("xmark.circle.fill",    "Sem disparo via WhatsApp",     true),
        ("checkmark.circle.fill","Disparo via WhatsApp",         false),
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.8).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {

                    // Header
                    VStack(spacing: 10) {
                        HStack {
                            Spacer()
                            Button { onClose() } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(Color(white: 0.4))
                            }
                        }

                        Image(systemName: "crown.fill")
                            .font(.system(size: 44))
                            .foregroundColor(Color(hex: "#FFD700"))

                        Text("PPPIX Premium")
                            .font(.title2.bold())
                            .foregroundColor(.white)

                        Text("Proteja mais. Sem limites.")
                            .font(.subheadline)
                            .foregroundColor(Color(white: 0.55))
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 20)

                    // Tabela comparativa
                    VStack(spacing: 0) {
                        // Cabeçalho
                        HStack {
                            Text("Funcionalidade")
                                .font(.caption.bold())
                                .foregroundColor(Color(white: 0.5))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("Free")
                                .font(.caption.bold())
                                .foregroundColor(Color(white: 0.5))
                                .frame(width: 50, alignment: .center)
                            Text("Premium")
                                .font(.caption.bold())
                                .foregroundColor(Color(hex: "#FFD700"))
                                .frame(width: 70, alignment: .center)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color(white: 0.08))

                        // Linhas
                        ForEach(Array(features.enumerated()), id: \.offset) { i, f in
                            HStack(spacing: 8) {
                                Image(systemName: f.icon)
                                    .font(.system(size: 13))
                                    .foregroundColor(f.free ? Color(white: 0.5) : Color(hex: "#FFD700"))
                                    .frame(width: 18)
                                Text(f.text)
                                    .font(.system(size: 13))
                                    .foregroundColor(f.free ? Color(white: 0.6) : .white)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                // Free
                                Image(systemName: f.free ? "checkmark" : "minus")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(f.free ? Color(hex: "#44FF88") : Color(white: 0.3))
                                    .frame(width: 50, alignment: .center)
                                // Premium
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(Color(hex: "#FFD700"))
                                    .frame(width: 70, alignment: .center)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(i % 2 == 0 ? Color(white: 0.05) : Color.clear)
                        }
                    }
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(white: 0.1), lineWidth: 1)
                    )
                    .padding(.horizontal, 20)

                    // Planos
                    VStack(spacing: 12) {

                        // Anual (destaque)
                        Button {
                            // TODO: iniciar compra anual via StoreKit
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 8) {
                                        Text("Plano Anual")
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundColor(.white)
                                        Text(PremiumManager.yearlyDiscount)
                                            .font(.caption.bold())
                                            .foregroundColor(Color(hex: "#0A0A12"))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(Color(hex: "#FFD700"))
                                            .cornerRadius(6)
                                    }
                                    Text("R$ 13,32/mês • cobrado anualmente")
                                        .font(.caption)
                                        .foregroundColor(Color(white: 0.6))
                                }
                                Spacer()
                                Text(PremiumManager.yearlyPrice)
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .padding(16)
                            .background(
                                LinearGradient(
                                    colors: [Color(hex: "#3366FF"), Color(hex: "#6633FF")],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                            .cornerRadius(14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color(hex: "#FFD700").opacity(0.4), lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)

                        // Mensal
                        Button {
                            // TODO: iniciar compra mensal via StoreKit
                        } label: {
                            HStack {
                                Text("Plano Mensal")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.white)
                                Spacer()
                                Text(PremiumManager.monthlyPrice + "/mês")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .padding(16)
                            .background(Color(white: 0.1))
                            .cornerRadius(14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color(white: 0.2), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                    Text("Cancele quando quiser · Renovação automática")
                        .font(.caption)
                        .foregroundColor(Color(white: 0.35))
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)
                        .padding(.bottom, 30)
                }
            }
            .background(Color(hex: "#0A0A12"))
            .cornerRadius(24)
            .padding(.horizontal, 12)
            .padding(.vertical, 40)
        }
    }
}
