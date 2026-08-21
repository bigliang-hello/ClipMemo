import Combine
import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system          // follow macOS system language
    case english = "en"
    case chinese = "zh-Hans"

    var id: String { rawValue }

    var displayNameKey: String {
        switch self {
        case .system: return "Follow System"
        case .english: return "English"
        case .chinese: return "简体中文"
        }
    }
}

/// In-app language switcher. Translations live in Localizable.xcstrings;
/// keys are the English source strings, zh-Hans values are looked up from
/// the compiled .lproj bundle of the chosen language.
@MainActor
final class L10n: ObservableObject {

    static let shared = L10n()

    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "appLanguage") }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: "appLanguage") ?? AppLanguage.system.rawValue
        language = AppLanguage(rawValue: raw) ?? .system
    }

    /// Locale used for user-visible dates/numbers.
    var locale: Locale {
        switch language {
        case .system: return Locale.current
        case .english: return Locale(identifier: "en_US")
        case .chinese: return Locale(identifier: "zh_CN")
        }
    }

    /// Translates `key` in the currently selected language. Missing
    /// translations fall back to the key itself (English source).
    func t(_ key: String) -> String {
        let code: String?
        switch language {
        case .system: code = nil
        case .english: code = "en"
        case .chinese: code = "zh-Hans"
        }
        if let code,
           let path = Bundle.main.path(forResource: code, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle.localizedString(forKey: key, value: key, table: nil)
        }
        // System mode: honor the OS language, falling back to the key.
        return Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }
}
