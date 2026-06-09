import SwiftUI

// MARK: - TextField

struct PPPIXTextField: View {

    let title: String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .sentences
    var onChange: ((String) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !title.isEmpty {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(Color(white: 0.6))
            }

            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(autocapitalization)
                .autocorrectionDisabled()
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color(hex: "#141422"))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(white: 0.15), lineWidth: 1)
                )
                .onChange(of: text, perform: { newValue in
                    onChange?(newValue)
                })
        }
    }
}

// MARK: - SecureField

struct PPPIXSecureField: View {

    let title: String
    let placeholder: String
    @Binding var text: String
    @Binding var showPassword: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !title.isEmpty {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(Color(white: 0.6))
            }

            HStack {
                Group {
                    if showPassword {
                        TextField(placeholder, text: $text)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    } else {
                        SecureField(placeholder, text: $text)
                    }
                }
                .foregroundColor(.white)

                Button {
                    showPassword.toggle()
                } label: {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                        .foregroundColor(Color(white: 0.5))
                        .font(.system(size: 16))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(hex: "#141422"))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(white: 0.15), lineWidth: 1)
            )
        }
    }
}

// MARK: - Button

struct PPPIXButton: View {

    let title: String
    var isLoading: Bool = false
    var style: ButtonStyle = .primary
    let action: () -> Void

    enum ButtonStyle {
        case primary, secondary, destructive
    }

    var body: some View {
        Button(action: action) {
            HStack {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.9)
                } else {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(style == .secondary ? Color(hex: "#3366FF") : .white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(backgroundGradient)
            .cornerRadius(12)
        }
        .disabled(isLoading)
        .opacity(isLoading ? 0.7 : 1)
    }

    private var backgroundGradient: LinearGradient {
        switch style {
        case .primary:
            return LinearGradient(
                colors: [Color(hex: "#3366FF"), Color(hex: "#6633FF")],
                startPoint: .leading, endPoint: .trailing
            )
        case .secondary:
            return LinearGradient(
                colors: [Color(hex: "#141422"), Color(hex: "#141422")],
                startPoint: .leading, endPoint: .trailing
            )
        case .destructive:
            return LinearGradient(
                colors: [Color(hex: "#FF3333"), Color(hex: "#CC0000")],
                startPoint: .leading, endPoint: .trailing
            )
        }
    }
}

// MARK: - Card

struct PPPIXCard<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .padding(16)
            .background(Color(hex: "#141422"))
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color(white: 0.1), lineWidth: 1)
            )
    }
}

// MARK: - Error Banner

struct ErrorBanner: View {
    let message: String
    var body: some View {
        if !message.isEmpty {
            Text(message)
                .font(.footnote)
                .foregroundColor(Color(hex: "#FF4444"))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(hex: "#FF4444").opacity(0.15))
                .cornerRadius(8)
        }
    }
}

// MARK: - Color extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
