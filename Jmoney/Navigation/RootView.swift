import AppKit
import GRDB
import SwiftUI

/// Window content: the auth gate when signed out, otherwise the main
/// NavigationSplitView with the sidebar, detail pane, sheets, and status bar.
///
/// It also owns two app-level jobs:
/// * **session restore** — the source's `AuthContext` boot sequence, which the
///   shell must complete before showing data (the local database is prepared
///   first, mirroring `initDB()` before navigation);
/// * **the sync runner** — anything in the app can raise `AppState.requestSync()`,
///   and this is the only place with the services needed to act on it.
struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(SessionStore.self) private var sessionStore
    @Environment(DatabaseService.self) private var database
    @Environment(AppearanceStore.self) private var appearance
    @Environment(SyncService.self) private var syncService

    var body: some View {
        @Bindable var appState = appState

        Group {
            if sessionStore.isAuthenticated {
                NavigationSplitView {
                    SidebarView()
                } detail: {
                    SectionDetailView()
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    StatusBarView()
                }
                .sheet(item: $appState.transactionEditor) { target in
                    TransactionEditorView(target: target)
                }
                .sheet(
                    isPresented: $appState.showQuickTransactionPicker,
                    onDismiss: openPendingQuickTransaction
                ) {
                    QuickTransactionPickerSheet()
                }
                .sheet(isPresented: $appState.showExportSheet) {
                    ExportSheetView()
                }
                .sheet(isPresented: $appState.showImportSheet) {
                    ImportSheetView()
                }
            } else {
                AuthGateView()
            }
        }
        // `_layout.tsx`'s `{isLocked ? <BiometricLock/> : <RootLayoutNav/>}` — the
        // lock covers everything, auth gate included.
        .overlay {
            if appState.isLocked {
                AppLockView(onUnlock: unlock)
            }
        }
        // The RN app's `app_theme` override, applied at the scene root so every
        // window (and the status bar) follows it. `nil` = follow the system.
        .preferredColorScheme(appearance.preference.colorScheme)
        .task {
            prepareDatabase()
            await restoreSession()
        }
        .task {
            // `onAuthStateChange`: a refresh or an external sign-out updates the
            // shell without polling.
            await sessionStore.observeSessionChanges()
        }
        // `_layout.tsx`'s launch check (`checkBiometrics` on mount).
        .onAppear {
            appState.isLocked = biometricsEnabled
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )) { _ in
            // `_layout.tsx`'s AppState listener: re-check on every activation.
            appState.isLocked = biometricsEnabled
        }
        .onChange(of: appState.syncRequestID) { _, _ in
            Task { await runFullSync() }
        }
        .onChange(of: appState.transactionSyncRequest) { _, request in
            guard let request else { return }
            Task { await runTransactionSync(isPartial: request.isPartial) }
        }
        .onChange(of: appState.entitySyncRequest) { _, request in
            guard let request else { return }
            Task { await runEntitySync(request.entity) }
        }
        .onChange(of: sessionStore.userId) { _, userId in
            appState.refreshLastSync(userId: userId)
        }
    }

    /// The quick-transaction picker hands its selection over as it closes; the
    /// editor then opens on top, which is the "one click to log a template" flow the
    /// RN app gets by routing to `add-transaction?quickTransaction=…`.
    private func openPendingQuickTransaction() {
        guard let template = appState.consumePendingQuickTransaction() else { return }
        appState.beginTransaction(from: template)
    }

    // MARK: - App lock

    /// `checkBiometrics`'s read: `use_biometrics === 'true'`.
    private var biometricsEnabled: Bool {
        BiometricPreference.isEnabled(in: .standard)
    }

    /// `onUnlock={() => setIsLocked(false)}`.
    private func unlock() {
        appState.isLocked = false
        appState.statusMessage = "Unlocked."
    }

    /// Mirrors the RN app's boot order: `initDB()` completes before navigation
    /// renders, then the session is restored.
    private func prepareDatabase() {
        database.prepare()
        if database.initializationError != nil {
            appState.statusMessage = "Local database failed to open."
        } else {
            appState.statusMessage = "Local database ready."
        }
    }

    /// `supabase.auth.getSession()`, bounded by `SessionStore`'s 7-second guard.
    private func restoreSession() async {
        await sessionStore.restore()
        appState.refreshLastSync(userId: sessionStore.userId)
    }

    /// `runFullSync` — the push-all then pull-all cycle behind ⌘R, the Settings
    /// row, and the dashboard's first-launch check.
    @MainActor
    private func runFullSync() async {
        guard let (userId, pool) = syncContext() else { return }
        let outcome = await syncService.runFullSync(userId: userId, writer: pool)
        finish(outcome, userId: userId)
    }

    /// `syncTransactions(userId, isPartial)` — the dashboard refresh button and the
    /// transactions screen's manual sync.
    @MainActor
    private func runTransactionSync(isPartial: Bool) async {
        guard let (userId, pool) = syncContext() else { return }
        let outcome = await syncService.syncTransactions(
            userId: userId,
            isPartial: isPartial,
            writer: pool
        )
        finish(outcome, userId: userId)
    }

    /// One entity's push-then-pull (`syncBudgets` and friends) — the management
    /// screens' manual sync buttons and their first-open guards. On success the
    /// `@initial_<entity>_sync_checked_` flag is written, which is what the
    /// source's `handleBudgetSync`/`handleGoalSync` do around their sync call.
    @MainActor
    private func runEntitySync(_ entity: SyncEntity) async {
        guard let (userId, pool) = syncContext() else { return }
        let outcome = await syncService.syncEntity(entity, userId: userId, writer: pool)
        finish(outcome, userId: userId, entity: entity)
    }

    /// A **push-only** run — the reorder toggles' `backgroundPush…`. The per-entity
    /// last-sync key is re-stamped here, mirroring what those fire-and-forget
    /// functions do after their push resolves.
    @MainActor
    private func runEntityPush(_ request: AppState.EntityPushRequest) async {
        guard let pool = database.pool else {
            appState.statusMessage = "Local database isn't ready."
            return
        }
        guard let userId = sessionStore.userId else { return }
        let outcome = await syncService.pushEntity(request.entity, userId: userId, writer: pool)
        switch outcome {
        case .completed, .alreadyRunning:
            UserDefaults.standard.set(
                SyncPreference.now, forKey: request.lastSyncKey
            )
            appState.markDataChanged()
        case .offline:
            appState.statusMessage = SyncError.offline.errorDescription
        case .failed(let message):
            appState.statusMessage = message
        }
    }

    /// The shared preamble: a ready pool and a signed-in user, then the status bar
    /// reports that a sync is under way.
    @MainActor
    private func syncContext() -> (String, DatabasePool)? {
        guard let pool = database.pool else {
            appState.statusMessage = "Local database isn't ready."
            return nil
        }
        guard let userId = sessionStore.userId else {
            appState.statusMessage = "Sign in to sync."
            return nil
        }
        appState.isSyncing = true
        return (userId, pool)
    }

    @MainActor
    private func finish(_ outcome: SyncService.Outcome, userId: String, entity: SyncEntity? = nil) {
        appState.isSyncing = false
        switch outcome {
        case .completed:
            if let entity {
                // `handleBudgetSync`/`handleGoalSync` write the flag after syncing.
                SyncPreference.markInitialSyncChecked(entity: entity, userId: userId)
                // `performGroupSync` re-stamps the groups screen's *own* key
                // (`@last_sync_groups_`), which is what stops its never-synced
                // guard from firing again — the pull itself wrote only the
                // `-transaction_groups_` spelling the sync module uses.
                if entity == .transactionGroups {
                    UserDefaults.standard.set(
                        SyncPreference.now,
                        forKey: SyncPreference.groupServiceLastSyncKey(userId: userId)
                    )
                }
            }
            appState.refreshLastSync(userId: userId)
            // Reload every open view: a pull can replace whole tables.
            appState.markDataChanged()
            appState.statusMessage = entity.map { "\($0.displayName) synced successfully." }
                ?? "Sync complete."
        case .offline:
            appState.statusMessage = SyncError.offline.errorDescription
        case .alreadyRunning:
            break
        case .failed(let message):
            appState.statusMessage = message
        }
    }
}

/// Routes the selected sidebar section to its feature view.
private struct SectionDetailView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        switch appState.selectedSection {
        case .dashboard: DashboardView()
        case .transactions: TransactionsView()
        case .budgets: BudgetsView()
        case .calendar: CalendarView()
        case .reports: ReportsView()
        case .goals: GoalsView()
        case .categories: CategoriesView()
        case .payees: PayeesView()
        case .groups: GroupsView()
        case .quickTransactions: QuickTransactionsView()
        case .settings: SettingsPaneView()
        }
    }
}
