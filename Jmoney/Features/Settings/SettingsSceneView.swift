import SwiftUI

/// The ⌘, Settings window.
///
/// macOS convention is a dedicated settings window; the source app only has a tab,
/// so both exist here and show the same `SettingsView`.
struct SettingsSceneView: View {
    @Environment(AppearanceStore.self) private var appearance

    var body: some View {
        SettingsView()
            .frame(width: 480, height: 620)
            .preferredColorScheme(appearance.preference.colorScheme)
    }
}
