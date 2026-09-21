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
