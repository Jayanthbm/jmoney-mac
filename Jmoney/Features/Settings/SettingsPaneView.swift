import SwiftUI

/// Settings pane shown when Settings is selected in the sidebar. Phase 13
/// replaces this with the full settings surface: appearance, daily reminders,
/// biometric lock, manage-data links, reset, sync, and account.
struct SettingsPaneView: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ContentUnavailableView {
            Label("Settings", systemImage: "gearshape")
        } description: {
            Text("Appearance, daily reminders, app lock, data management, and account settings live here.")
        } actions: {
            Button("Open Settings Window") {
                openSettings()
            }
        }
        .navigationTitle("Settings")
    }
}
