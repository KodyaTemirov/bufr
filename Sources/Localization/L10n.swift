import Foundation

/// Resolve language code from UserDefaults (thread-safe, no MainActor dependency)
private func resolvedLanguageCode() -> String {
    let raw = UserDefaults.standard.string(forKey: "appLanguage") ?? ""
    let lang = AppLanguage(rawValue: raw) ?? .system
    return lang.code
}

/// Localization helper. Loads strings from the correct .lproj bundle
/// based on the current app language setting.
func L10n(_ key: String) -> String {
    let code = resolvedLanguageCode()

    guard let bundlePath = Bundle.module.path(forResource: code, ofType: "lproj"),
          let bundle = Bundle(path: bundlePath)
    else {
        return Bundle.module.localizedString(forKey: key, value: key, table: nil)
    }

    return bundle.localizedString(forKey: key, value: key, table: nil)
}

/// Format localized string with arguments
func L10n(_ key: String, _ args: CVarArg...) -> String {
    let format = L10n(key)
    return String(format: format, arguments: args)
}
