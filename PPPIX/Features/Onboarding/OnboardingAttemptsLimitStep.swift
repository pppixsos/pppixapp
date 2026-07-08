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
            // Verifica se já existem senhas cadastradas
            // Se sim, usa PATCH para atualizar; se não, usa POST para criar
            let existing = try? await APIClient.shared.getPasswords()
            let existingId = existing?.first?.id

            if let existingId {
                // Já tem senhas — atualiza via PATCH
                try await APIClient.shared.updatePasswordSettings(
                    id: existingId,
                    body: PasswordAttemptsRequest(
                        max_wrong_attempts: maxAttempts,
                        reset_attempts_after_minutes: 60
                    )
                )
                // Atualiza as senhas também
                try? await APIClient.shared.updatePasswords(
                    id: existingId,
                    body: SetPasswordsRequest(
                        bank_password: data.bankPassword,
                        ppix_password: data.ppixPassword,
                        emergency_password: data.emergencyPassword
                    )
                )
            } else {
                // Não tem senhas — cria via POST
                try await APIClient.shared.setPasswords(body: SetPasswordsRequest(
                    bank_password: data.bankPassword,
                    ppix_password: data.ppixPassword,
                    emergency_password: data.emergencyPassword
                ))

                // Busca o ID recém-criado para salvar o limite de tentativas
                var settingsId: Int?
                for attempt in 0..<3 {
                    if let list = try? await APIClient.shared.getPasswords(),
                       let settings = list.first,
                       let id = settings.id {
                        settingsId = id
                        break
                    }
                    if attempt < 2 {
                        try? await Task.sleep(nanoseconds: 400_000_000)
                    }
                }

                if let settingsId {
                    try? await APIClient.shared.updatePasswordSettings(
                        id: settingsId,
                        body: PasswordAttemptsRequest(
                            max_wrong_attempts: maxAttempts,
                            reset_attempts_after_minutes: 60
                        )
                    )
                }
            }

            SessionManager.shared.arePasswordsConfigured = true
            isSaving = false
            onNext()

        } catch APIError.badRequest(let msg) {
            errorMessage = msg
            isSaving = false
        } catch {
            errorMessage = "Erro ao salvar senhas. Verifique sua internet e tente novamente."
            isSaving = false
        }
    }
}
