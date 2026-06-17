import UIKit

/// Gerencia a troca do ícone (e nome de exibição associado) do app entre
/// o ícone original do PPPIX e um conjunto de disfarces. Usa a API oficial
/// `setAlternateIconName` da Apple — aprovada para uso em produção desde
/// que a troca só ocorra por ação explícita do usuário dentro do app
/// (Guideline 4.6) e seja possível reverter ao ícone original.
enum AppDisguise: String, CaseIterable, Identifiable {
    case calculator = "AppIcon-Calculator"
    case notes = "AppIcon-Notes"
    case flashlight = "AppIcon-Flashlight"
    case weather = "AppIcon-Weather"
    case compass = "AppIcon-Compass"
    case converter = "AppIcon-Converter"
    case timer = "AppIcon-Timer"

    var id: String { rawValue }

    /// Nome de exibição que aparece embaixo do ícone na Tela de Início
    /// quando este disfarce está ativo.
    var displayName: String {
        switch self {
        case .calculator: return "Calculadora"
        case .notes: return "Notas"
        case .flashlight: return "Lanterna"
        case .weather: return "Clima"
        case .compass: return "Bússola"
        case .converter: return "Conversor"
        case .timer: return "Cronômetro"
        }
    }

    /// Nome do asset do ícone (igual ao rawValue) — usado para pré-visualização.
    var previewAssetName: String { rawValue }

    var sfSymbol: String {
        switch self {
        case .calculator: return "plusminus.circle.fill"
        case .notes: return "note.text"
        case .flashlight: return "flashlight.on.fill"
        case .weather: return "cloud.sun.fill"
        case .compass: return "safari.fill"
        case .converter: return "dollarsign.circle.fill"
        case .timer: return "timer"
        }
    }
}

@MainActor
final class AppDisguiseManager: ObservableObject {
    static let shared = AppDisguiseManager()
    private init() {
        currentDisguise = AppDisguise(rawValue: UIApplication.shared.alternateIconName ?? "")
    }

    @Published private(set) var currentDisguise: AppDisguise?

    var isDisguised: Bool { currentDisguise != nil }

    /// Aplica um disfarce. Passe `nil` para voltar ao ícone original do PPPIX.
    func apply(_ disguise: AppDisguise?, completion: @escaping (Bool) -> Void) {
        guard UIApplication.shared.supportsAlternateIcons else {
            completion(false)
            return
        }
        UIApplication.shared.setAlternateIconName(disguise?.rawValue) { [weak self] error in
            DispatchQueue.main.async {
                if error == nil {
                    self?.currentDisguise = disguise
                    completion(true)
                } else {
                    completion(false)
                }
            }
        }
    }
}
