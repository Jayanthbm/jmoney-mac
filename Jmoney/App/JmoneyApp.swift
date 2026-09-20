import SwiftUI

@main
struct JmoneyApp: App {
    /// UI shell state (navigation, sheets, search requests, status bar).
    @State private var appState = AppState()
    /// Signed-in session. Mock until Phase 14 (Supabase + Keychain).
    @State private var sessionStore = SessionStore()

    var body: some Scene {
        WindowGroup("Jmoney") {
            RootView()
                .environment(appState)
                .environment(sessionStore)
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
