import SwiftUI

/// Settings as shown in the sidebar's detail pane.
///
/// This is the React Native app's Settings *tab* — the same surface the ⌘, window
/// shows, so both host the shared `SettingsView` rather than diverging.
struct SettingsPaneView: View {
    var body: some View {
        SettingsView()
    }
}
