import SwiftUI

@main
struct JmoneyApp: App {
    /// UI shell state (navigation, sheets, search requests, status bar).
    @State private var appState = AppState()
    /// Local SQLite store (WAL) + migrations. Cheap to construct; the pool
    /// opens and migrates on first `prepare()`.
    @State private var database = DatabaseService()
    /// Appearance override (the RN app's `app_theme`). Shared with the Settings
    /// scene so ⌘, and the sidebar agree.
    @State private var appearance = AppearanceStore()

    /// Auth + sync, resolved once from build configuration.
    ///
    /// Resolving here rather than per-view means an unconfigured build is decided
    /// at launch: the services become honest stubs and the auth gate says why.
    private let cloud: CloudServices
    @State private var sessionStore: SessionStore

    init() {
        let cloud = CloudFactory.make()
        self.cloud = cloud
        _sessionStore = State(
            initialValue: SessionStore(
                auth: cloud.auth,
                configurationMessage: cloud.unavailable?.message
            )
        )
    }

    var body: some Scene {
        WindowGroup("Jmoney") {
            RootView()
                .environment(appState)
                .environment(sessionStore)
                .environment(database)
                .environment(appearance)
                .environment(cloud.sync)
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
                .environment(cloud.sync)
        }
    }
}
