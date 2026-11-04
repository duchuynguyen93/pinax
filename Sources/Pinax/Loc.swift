import Foundation

// MARK: - Localization (English / Tiếng Việt)

enum Lang { case en, vi }

enum LangPref: Int, CaseIterable, Identifiable {
    case system = 0, english, vietnamese
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .system: return L("System", "Theo hệ thống")
        case .english: return "English"
        case .vietnamese: return "Tiếng Việt"
        }
    }
    var resolved: Lang {
        switch self {
        case .english: return .en
        case .vietnamese: return .vi
        case .system:
            let code = Locale.preferredLanguages.first ?? "en"
            return code.hasPrefix("vi") ? .vi : .en
        }
    }
}

enum Loc { static var lang: Lang = LangPref.system.resolved }

/// Chuỗi theo ngôn ngữ hiện tại.
func L(_ en: String, _ vi: String) -> String { Loc.lang == .vi ? vi : en }
