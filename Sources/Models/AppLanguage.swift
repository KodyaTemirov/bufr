import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case russian = "ru"
    case uzbek = "uz"
    case english = "en"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "Система / System"
        case .russian: "Русский"
        case .uzbek: "O'zbekcha"
        case .english: "English"
        }
    }

    /// Resolves `.system` to the actual language based on OS locale
    var resolved: AppLanguage {
        guard self == .system else { return self }
        let preferred = Locale.preferredLanguages.first ?? "en"
        if preferred.hasPrefix("uz") { return .uzbek }
        if preferred.hasPrefix("ru") { return .russian }
        return .english
    }

    var code: String {
        switch self {
        case .system: resolved.code
        case .russian: "ru"
        case .uzbek: "uz"
        case .english: "en"
        }
    }
}
