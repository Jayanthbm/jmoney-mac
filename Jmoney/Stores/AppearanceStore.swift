import Observation
import SwiftUI

/// Owns the appearance preference so the main window and the ⌘, Settings window
/// show and set the same value.
///
/// The React Native app keeps this in `ThemeContext`'s state; on macOS it has to
/// be observable above both scenes, hence a small store rather than state inside
/// the settings view.
@Observable
final class AppearanceStore {
    private(set) var preference: AppearancePreference
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.preference = AppearancePreference.stored(in: defaults)
    }

    /// `toggleTheme()`, generalized to three choices. Persists immediately, as the
    /// source writes `app_theme` on every change.
    func select(_ preference: AppearancePreference) {
        guard preference != self.preference else { return }
        self.preference = preference
        AppearancePreference.save(preference, in: defaults)
    }

    /// Re-reads the stored value — used after a data reset clears the key.
    func reload() {
        preference = AppearancePreference.stored(in: defaults)
    }
}
