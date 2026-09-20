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

    var body: some Scene {
        WindowGroup("Jmoney") {
            RootView()
                .environment(appState)
                .environment(sessionStore)
                .environment(database)
                .frame(minWidth: 1000, minHeight: 640)
        }
        .commands {
            AppCommands(appState: appState)
        }

        Settings {
            SettingsSceneView()
                .environment(appState)
                .environment(sessionStore)
        }
    }
}
