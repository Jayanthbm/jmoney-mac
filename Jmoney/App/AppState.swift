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

    var showNewTransaction = false
    var showQuickTransactionPicker = false

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
