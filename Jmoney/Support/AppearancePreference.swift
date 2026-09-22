import SwiftUI

/// The app's appearance override.
///
/// Ports `ThemeContext.tsx`: the source stores `app_theme` as `"light"` or
/// `"dark"`, and when the key is **absent** it falls back to the system scheme
/// (`Appearance.getColorScheme()`). Its settings screen only offers Light and
/// Dark, so once the user has picked one there is no way back to following the
/// system — an omission in that screen, not a rule (DATA_ARCHITECTURE.md §1.5).
///
/// macOS therefore offers the three choices explicitly, with `system` mapped onto
/// the source's "key absent" state. The stored data, the key name and the default
/// behavior are unchanged; the fallback is merely reachable.
enum AppearancePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    /// The key the source uses (`AsyncStorage` there, `UserDefaults` here).
    static let storageKey = "app_theme"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var systemImage: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    /// `nil` for `.system`, so SwiftUI follows the system appearance — which is
    /// also the state the source is in while the key is unwritten.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// `stored ? stored === 'dark' : system` — the source's read, with any
    /// unrecognized value treated as "unset" rather than crashing.
    static func stored(in defaults: UserDefaults = .standard) -> AppearancePreference {
        switch defaults.string(forKey: storageKey) {
        case "light": return .light
        case "dark": return .dark
        default: return .system
        }
    }

    /// `toggleTheme()`'s write. Selecting System removes the key, exactly as the
    /// source behaves before the user's first choice.
    static func save(_ preference: AppearancePreference, in defaults: UserDefaults = .standard) {
        if preference == .system {
            defaults.removeObject(forKey: storageKey)
        } else {
            defaults.set(preference.rawValue, forKey: storageKey)
        }
    }
}
