import SwiftUI

/// The ⌘, Settings window. Phase 13 fills in appearance, reminders, app lock,
/// data management, sync, and account rows.
struct SettingsSceneView: View {
    @Environment(SessionStore.self) private var sessionStore

    var body: some View {
        Form {
            Section("Account") {
                LabeledContent(
                    "Signed in as",
                    value: sessionStore.userEmail ?? "Signed out"
                )
            }
            Section("General") {
                LabeledContent("Version", value: "0.1.0")
                Text("Full settings arrive with the data and sync layers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
    }
}
