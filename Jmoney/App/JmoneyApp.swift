import SwiftUI

@main
struct JmoneyApp: App {
    /// UI shell state (navigation, sheets, search requests, status bar).
    @State private var appState = AppState()
    /// Signed-in session. Mock until Phase 14 (Supabase + Keychain).
    @State private var sessionStore = SessionStore()
    /// Local SQLite store (WAL) + migrations. Cheap to construct; the pool
    /// opens and migrates on first `prepare()`.
    @State private var database = DatabaseService()
    /// Appearance override (the RN app's `app_theme`). Shared with the Settings
    /// scene so ⌘, and the sidebar agree.
    @State private var appearance = AppearanceStore()

    var body: some Scene {
        WindowGroup("Jmoney") {
            RootView()
                .environment(appState)
                .environment(sessionStore)
                .environment(database)
                .environment(appearance)
                .frame(minWidth: 1000, minHeight: 640)
        }
        .commands {
            AppCommands(appState: appState)
        }

        Settings {
            SettingsSceneView()
                .environment(appState)
                .environment(sessionStore)
                .environment(database)
                .environment(appearance)
        }
    }
}
