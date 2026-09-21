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

    func requestSync() {
        // The sync engine (GRDB + Supabase) arrives with the data layer.
        statusMessage = "Sync isn't connected yet."
    }
}
