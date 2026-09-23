import Foundation
import Observation

/// Central UI state for the app shell.
///
/// Phase 4 scope: sidebar selection, sheet presentation, search requests, and the
/// status-bar message channel. Data-layer stores (database, sync) attach in later
/// phases and surface their progress through the same status bar.
@Observable
final class AppState {
    // MARK: Navigation

    var selectedSection: AppSection = .dashboard

    // MARK: Sheets

    /// Non-nil while the transaction editor sheet is open — `.new` from ⌘N, or
    /// `.edit(tx)` when a row asks to be edited.
    var transactionEditor: TransactionEditorTarget?

    var showQuickTransactionPicker = false

    /// A template chosen in the picker, waiting for that sheet to close before the
    /// editor opens. Presenting a second sheet from inside the first is unreliable,
    /// so the picker's dismissal carries it through (`consumePendingQuickTransaction`).
    private(set) var pendingQuickTransaction: QuickTransaction?

    /// Called by the picker: close it, and remember what to log.
    func logQuickTransaction(_ template: QuickTransaction) {
        pendingQuickTransaction = template
        showQuickTransactionPicker = false
    }

    /// Reads and clears the template the picker selected, if any.
    func consumePendingQuickTransaction() -> QuickTransaction? {
        defer { pendingQuickTransaction = nil }
        return pendingQuickTransaction
    }

    /// Bumped whenever local data changes, so any open view can reload. Replaces
    /// the RN app's `DeviceEventEmitter 'module_refreshed'` events.
    private(set) var dataRevision = 0

    func markDataChanged() {
        dataRevision += 1
    }

    func beginNewTransaction() {
        transactionEditor = .new
    }

    func editTransaction(_ transaction: Transaction) {
        transactionEditor = .edit(transaction)
    }

    /// Opens the editor on a quick-transaction template, which prefills the fields
    /// the source's `quickTransaction` route param prefills. This is the ⌘⇧N /
    /// bolt-button path.
    func beginTransaction(from template: QuickTransaction) {
        transactionEditor = .template(template)
    }

    // MARK: - Cross-section transaction filters

    /// A pre-filtered Transactions screen, requested by another section.
    ///
    /// Replaces the RN app's `router.push({ pathname: '/(tabs)/transactions',
    /// params: { initialSelectedCats }})`: the categories and payees screens hand the
    /// selected ids over, select the section, and `TransactionsView` consumes them.
    /// Groups have no such path in the source — a group tap opens its editor.
    struct TransactionFilterRequest: Equatable {
        var categoryIds: [String] = []
        var payeeIds: [String] = []

        var isEmpty: Bool { categoryIds.isEmpty && payeeIds.isEmpty }
    }

    private(set) var requestedTransactionFilters: TransactionFilterRequest?

    /// Bumped on every request, so a second click on the same category still
    /// reloads the destination (a value comparison would not).
    private(set) var transactionFilterRequestID = 0

    func openTransactions(filters: TransactionFilterRequest) {
        requestedTransactionFilters = filters
        transactionFilterRequestID += 1
        selectedSection = .transactions
    }

    /// Reads and clears the pending filter request, so the Transactions section
    /// applies each request exactly once.
    func consumeRequestedTransactionFilters() -> TransactionFilterRequest? {
        defer { requestedTransactionFilters = nil }
        return requestedTransactionFilters
    }

    /// Report another section asked for (dashboard click-through). The reports
    /// section pushes it and clears it through `consumeRequestedReport()`.
    private(set) var requestedReport: ReportDestination?

    func openReport(_ destination: ReportDestination) {
        requestedReport = destination
        selectedSection = .reports
    }

    /// Reads and clears the pending click-through, so the reports section pushes
    /// each requested report exactly once.
    func consumeRequestedReport() -> ReportDestination? {
        defer { requestedReport = nil }
        return requestedReport
    }

    // MARK: Search

    /// Incremented to ask the frontmost searchable view (currently Transactions)
    /// to present and focus its search field. Lets ⌘F work from any section.
    private(set) var searchRequestID = 0

    func requestSearchFocus() {
        searchRequestID += 1
    }

    // MARK: Status bar

    /// Transient message shown in the status bar. Replaces the React Native
    /// app's toasts; errors become alerts once real flows land.
    var statusMessage: String?

    var isSyncing = false
    var lastSyncDate: Date?

    var lastSyncText: String {
        AppFormat.relativeTime(lastSyncDate)
    }

    /// Re-reads the persisted full-sync timestamp (`@last_sync_master_<userId>`, the
    /// key the source writes at the end of `runFullSync`).
    func refreshLastSync(userId: String?) {
        lastSyncDate = SyncPreference.lastFullSync(userId: userId)
    }

    // MARK: - Sync requests

    /// Bumped to ask for a full sync. The root view owns the runner (it holds the
    /// services), so a toolbar button, a menu item or the Settings row only has to
    /// raise the request — the same shape as `searchRequestID`.
    private(set) var syncRequestID = 0

    func requestSync() {
        syncRequestID += 1
    }

    /// A transactions-only sync request (`syncTransactions`).
    struct TransactionSyncRequest: Equatable {
        /// Distinguishes two identical requests, so a second click still runs.
        var id: Int
        /// `false` is the source's force resync (wipe local transactions and
        /// re-pull everything).
        var isPartial: Bool
    }

    private(set) var transactionSyncRequest: TransactionSyncRequest?

    func requestTransactionSync(isPartial: Bool = true) {
        transactionSyncRequest = TransactionSyncRequest(
            id: (transactionSyncRequest?.id ?? 0) + 1,
            isPartial: isPartial
        )
    }

    /// A one-entity sync request, used by the four management screens' first-open
    /// guards (`syncBudgets` and friends).
    struct EntitySyncRequest: Equatable {
        var id: Int
        var entity: SyncEntity
    }

    private(set) var entitySyncRequest: EntitySyncRequest?

    func requestEntitySync(_ entity: SyncEntity) {
        entitySyncRequest = EntitySyncRequest(id: (entitySyncRequest?.id ?? 0) + 1, entity: entity)
    }

    /// A **push-only** request for one entity. The reorder toggles of categories,
    /// payees, groups and quick transactions call `backgroundPush…` when they are
    /// *exited* — dirty priority rows go up, no pull comes back, and the per-entity
    /// last-sync key is re-stamped. `RootView` owns the runner.
    struct EntityPushRequest: Equatable {
        var id: Int
        var entity: SyncEntity
        /// The storage key each `backgroundPush…` re-stamps after pushing
        /// (`SyncService.pushEntity` is fire-and-forget, so the caller writes it).
        var lastSyncKey: String
    }

    private(set) var entityPushRequest: EntityPushRequest?

    func requestEntityPush(_ entity: SyncEntity, userId: String?) {
        guard let userId else { return }
        entityPushRequest = EntityPushRequest(
            id: (entityPushRequest?.id ?? 0) + 1,
            entity: entity,
            lastSyncKey: SyncPreference.lastSyncKey(entity: entity, userId: userId)
        )
    }

    // MARK: - Section editor requests (Phase 16)

    /// Asks the **frontmost section** to present its new-item editor. The File
    /// menu's New Budget/Goal/Category/… items raise this; only the visible
    /// section's list view is alive to observe it, so exactly one editor answers.
    /// Views select nothing and simply present — the menu item first switches to
    /// the section it names.
    private(set) var sectionEditorRequestID = 0

    func requestSectionEditor() {
        sectionEditorRequestID += 1
    }

    /// Bumped when the Data menu asks the frontmost management section to sync
    /// its own entity (the same request the screens' toolbar buttons raise).
    private(set) var sectionSyncRequestID = 0

    func requestSectionSync() {
        sectionSyncRequestID += 1
    }

    // MARK: - Import / Export (Phase 15 — macOS-original feature)

    /// Presents the export sheet (File > Export…, ⌘E).
    var showExportSheet = false

    /// Presents the import sheet (File > Import Transactions…).
    var showImportSheet = false

    /// The Transactions screen's current filter state, recorded on every reload
    /// so the export sheet can offer "what's on screen" without the shell owning
    /// filter construction. `nil` = the Transactions screen hasn't loaded yet.
    var transactionsFilters: TransactionService.Filters?

    // MARK: - App lock (the RN `BiometricLock` overlay)

    /// True while the window is covered by the lock overlay. The RN `_layout.tsx`
    /// sets this at launch and on every re-activation when `use_biometrics` is
    /// `'true'`; `RootView` mirrors that lifecycle and reads the preference itself,
    /// so no lock request has to carry the flag around.
    var isLocked = false

    /// True while a LocalAuthentication prompt (the lock screen's unlock, or the
    /// enable flow's biometric check) is on screen.
    ///
    /// On macOS the auth sheet itself churns the app's activation state, so
    /// `RootView` suppresses its re-lock-on-`didBecomeActive` while this is set —
    /// without the guard, the sheet's own presentation can immediately re-arm the
    /// lock on top of a *successful* authentication.
    var isAuthPromptActive = false
}
