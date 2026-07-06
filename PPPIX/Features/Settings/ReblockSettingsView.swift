import SwiftUI

struct ReblockSettingsView: View {

    @ObservedObject private var premium = PremiumManager.shared
    @State private var selectedSeconds: Int = ReblockSettings.current
    @State private var showPaywall = false
    @Environment(\.dismiss) private var dismiss

    private let options: [(label: String, seconds: Int)] = [
        ("30 segundos", 30),
        ("1 minuto",    60),
        ("1 min 30s",   90),
        ("2 minutos",   120),
        ("2 min 30s",   150),
        ("3 minutos",   180),
    ]

    var body: some View {
        ZStack {
            Color(hex: "#0A0A12").ignoresSafeArea()
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Image(systemName: "timer")
                            .font(.system(size: 40))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(hex: "#3366FF"), Color(hex: "#6633FF")],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                        Text("Tempo de Rebloqueio")
                            .font(.title3.bold())
                            .foregroundColor(.white)
                        Text("Defina por quanto tempo o app ficará desbloqueado após você digitar a senha.")
                            .font(.subheadline)
                            .foregroundColor(Color(white: 0.5))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    .padding(.top, 8)

                    if !premium.isPremium {
                        HStack(spacing: 10) {
                            Image(systemName: "crown.fill")
                                .foregroundColor(Color(hex: "#FFD700"))
                                .font(.system(size: 14))
                            Text("Apenas usuários Premium podem alterar este tempo")
                                .font(.caption)
                                .foregroundColor(Color(white: 0.6))
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity)
                        .background(Color(hex: "#FFD700").opacity(0.08))
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#FFD700").opacity(0.2), lineWidth: 1))
                    }

                    VStack(spacing: 10) {
                        ForEach(options, id: \.seconds) { option in
                            optionRow(option: option)
                        }
                    }

                    HStack(spacing: 10) {
                        Image(systemName: "info.circle")
                            .foregroundColor(Color(white: 0.3))
                            .font(.system(size: 13))
                        Text("Após esse tempo, o app será rebloqueado automaticamente mesmo com o celular em uso.")
                            .font(.caption)
                            .foregroundColor(Color(white: 0.35))
                            .lineSpacing(3)
                    }
                    .padding(14)
                    .background(Color(white: 0.04))
                    .cornerRadius(12)

                    if premium.isPremium {
                        Button {
                            ReblockSettings.save(seconds: selectedSeconds)
                            dismiss()
                        } label: {
                            Text("Salvar")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(LinearGradient(colors: [Color(hex: "#3366FF"), Color(hex: "#6633FF")], startPoint: .leading, endPoint: .trailing))
                                .cornerRadius(14)
                        }
                    } else {
                        Button { showPaywall = true } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "crown.fill").font(.system(size: 14))
                                Text("Assinar Premium para alterar").font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(LinearGradient(colors: [Color(hex: "#FFB700"), Color(hex: "#FF8C00")], startPoint: .leading, endPoint: .trailing))
                            .cornerRadius(14)
                        }
                    }

                    Spacer(minLength: 20)
                }
                .padding(20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Rebloqueio")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showPaywall) {
            PremiumPaywallView(onClose: { showPaywall = false })
        }
    }

    private func optionRow(option: (label: String, seconds: Int)) -> some View {
        let isSelected = selectedSeconds == option.seconds
        let isDefault  = option.seconds == 30
        let isDisabled = !premium.isPremium && !isDefault
        return Button {
            if premium.isPremium { selectedSeconds = option.seconds }
            else if isDefault { selectedSeconds = option.seconds }
            else { showPaywall = true }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(isSelected ? Color(hex: "#3366FF") : Color(white: 0.15), lineWidth: 2).frame(width: 22, height: 22)
                    if isSelected { Circle().fill(Color(hex: "#3366FF")).frame(width: 12, height: 12) }
                }
                Text(option.label)
                    .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isDisabled ? Color(white: 0.25) : .white)
                Spacer()
                if isDefault {
                    Text("PADRÃO").font(.system(size: 10, weight: .bold)).foregroundColor(Color(hex: "#3366FF"))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color(hex: "#3366FF").opacity(0.12)).cornerRadius(5)
                }
                if isDisabled { Image(systemName: "lock.fill").font(.system(size: 12)).foregroundColor(Color(white: 0.2)) }
            }
            .padding(16)
            .background(isSelected ? Color(hex: "#3366FF").opacity(0.1) : Color(white: isDisabled ? 0.03 : 0.05))
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(isSelected ? Color(hex: "#3366FF").opacity(0.5) : Color(white: 0.07), lineWidth: isSelected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - ReblockSettings

enum ReblockSettings {
    private static let key = "pppix_reblock_seconds"
    private static let defaults = UserDefaults(suiteName: "group.tech.pppix.app")

    static var current: Int {
        let v = defaults?.integer(forKey: key) ?? 0
        return v > 0 ? v : 30
    }

    static func save(seconds: Int) {
        defaults?.set(seconds, forKey: key)
        defaults?.synchronize()
    }
}
