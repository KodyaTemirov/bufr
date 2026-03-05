import Foundation

/// Resolve language code from UserDefaults (thread-safe, no MainActor dependency)
private func resolvedLanguageCode() -> String {
    let raw = UserDefaults.standard.string(forKey: "appLanguage") ?? ""
    let lang = AppLanguage(rawValue: raw) ?? .system
    return lang.code
}

/// Find the bundle containing localization resources.
/// SPM's Bundle.module looks in Bufr.app/ root which breaks codesign,
/// so we search in Contents/Resources/ (where the build script places Bufr_Bufr.bundle).
private func localizationBundle() -> Bundle {
    let resourcesURL = Bundle.main.resourceURL ?? Bundle.main.bundleURL
    let candidates = [
        resourcesURL.appendingPathComponent("Bufr_Bufr.bundle"),
        Bundle.main.bundleURL.appendingPathComponent("Bufr_Bufr.bundle"),
    ]
    for url in candidates {
        if let b = Bundle(url: url) { return b }
    }
    return Bundle.main
}

private let _localizationBundle: Bundle = localizationBundle()

/// Localization helper. Loads strings from the correct .lproj bundle
/// based on the current app language setting.
func L10n(_ key: String) -> String {
    let code = resolvedLanguageCode()

    guard let lproj = _localizationBundle.url(forResource: code, withExtension: "lproj"),
          let bundle = Bundle(url: lproj)
    else {
        return _localizationBundle.localizedString(forKey: key, value: key, table: nil)
    }

    return bundle.localizedString(forKey: key, value: key, table: nil)
}

/// Format localized string with arguments
func L10n(_ key: String, _ args: CVarArg...) -> String {
    let format = L10n(key)
    return String(format: format, arguments: args)
}
