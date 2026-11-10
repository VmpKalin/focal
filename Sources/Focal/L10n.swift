import Foundation

/// Interface language. "System" follows the first preferred language in macOS settings.
enum Language: String, CaseIterable {
    case system, en, uk
}

enum L10n {
    /// Forces a language regardless of the setting (README renders are always English).
    static var override: Language?

    static var current: Language {
        override ?? Language(rawValue: UserDefaults.standard.string(forKey: Prefs.Key.language) ?? "") ?? .system
    }

    static var isUkrainian: Bool {
        switch current {
        case .uk: return true
        case .en: return false
        case .system: return Locale.preferredLanguages.first?.hasPrefix("uk") ?? false
        }
    }
}

/// UI text: the English and Ukrainian versions side by side, so a translation never drifts from its source.
func tr(_ en: String, _ uk: String) -> String { L10n.isUkrainian ? uk : en }
