import SwiftUI

struct OnboardingAttemptsLimitStep: View {
    @ObservedObject var data: OnboardingData
    let onBack: () -> Void
    let onNext: () -> Void

    @State private var maxAttempts = 3
    @State private var isSaving = false
    @State private var errorMessage = ""

    private let attemptOptions = Array(1...10)

    var body: some View {
        OnboardingStepShell(
            icon: "exclamationmark.shield.fill",
            iconColor: Color(hex: "#FF6600"),
            title: "Limite de tentativas erradas",
            subtitle: "Se alguém errar a senha mais vezes que esse limite, um alerta é enviado automaticamente para seus contatos de emergência.",
            stepIndex: 8,
            totalSteps: 13,
            onBack: onBack
        ) {
            VStack(spacing: 18) {
                Picker("Tentativas", selection: $maxAttempts) {
                    ForEach(attemptOptions, id: \.self) { n in
                        Text("\(n) tentativa\(n > 1 ? "s" : "")").tag(n)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 120)
                .clipped()
                .background(Color(hex: "#141422"))
                .cornerRadius(14)

                if !errorMessage.isEmpty { ErrorBanner(message: errorMessage) }

                PPPIXButton(title: "Salvar e continuar", isLoading: isSaving) {
                    Task { await saveAndNext() }
                }
            }
        }
    }

    private func saveAndNext() async {
        isSaving = true
        errorMessage = ""

        do {
            try await APIClient.shared.setPasswords(body: SetPasswordsRequest(
                bank_password: data.bankPassword,
                ppix_password: data.ppixPassword,
                emergency_password: data.emergencyPassword
            ))
            SessionManager.shared.arePasswordsConfigured = true

            // Busca o ID recém-criado para salvar o limite de tentativas
            if let list = try? await APIClient.shared.getPasswords(),
               let settings = list.first,
               let settingsId = settings.id {
                try? await APIClient.shared.updatePasswordSettings(
                    id: settingsId,
                    body: PasswordAttemptsRequest(
                        max_wrong_attempts: maxAttempts,
                        reset_attempts_after_minutes: 60
                    )
                )
            }

            isSaving = false
            onNext()
        } catch APIError.badRequest(let msg) {
            errorMessage = msg
            isSaving = false
        } catch {
            errorMessage = "Erro ao salvar senhas. Tente novamente."
            isSaving = false
        }
    }
}
