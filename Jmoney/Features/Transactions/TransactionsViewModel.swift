import Foundation
import GRDB
import Observation

/// Transactions list state: filters, the day-sectioned page, lookups for the
/// filter popovers, the last-five-months statistics, and soft deletion.
///
/// Replaces the RN `useTransactionFilters` hook. The `module_refreshed` event bus
/// has no macOS equivalent — views reload when they appear, when
/// `AppState.dataRevision` changes, or via the toolbar.
@Observable
final class TransactionsViewModel {
    private(set) var filters = TransactionService.Filters()
    private(set) var page = TransactionService.ListPage()
    private(set) var lookups = TransactionService.Lookups.empty
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private(set) var statistics: [TransactionService.MonthlyStat] = []
    private(set) var isLoadingStatistics = false

    /// Rows currently on screen, flattened across day sections.
    var transactions: [Transaction] { page.transactions }

    // MARK: - Filter summary

    /// RN `getFilterSummaryText`, e.g. "21 Sep - 30 Sep • 2 Cats • 1 Payee".
    /// The entity filters contribute counts rather than names.
    var filterSummaryText: String {
        var parts: [String] = []

        if filters.startDate != nil || filters.endDate != nil {
            if let start = filters.startDate, let end = filters.endDate {
                parts.append("\(AppFormat.dayMonth(start)) - \(AppFormat.dayMonth(end))")
            } else if let start = filters.startDate {
                parts.append("From \(AppFormat.dayMonth(start))")
            } else if let end = filters.endDate {
                parts.append("To \(AppFormat.dayMonth(end))")
            }
        }

        let categories = filters.categoryIds.count
        if categories > 0 { parts.append("\(categories) Cat\(categories > 1 ? "s" : "")") }
        let payees = filters.payeeIds.count
        if payees > 0 { parts.append("\(payees) Payee\(payees > 1 ? "s" : "")") }
        let groups = filters.groupIds.count
        if groups > 0 { parts.append("\(groups) Group\(groups > 1 ? "s" : "")") }

        return parts.joined(separator: " • ")
    }

    // MARK: - Mutations

    func setSearch(_ text: String) {
        guard filters.search != text else { return }
        filters.search = text
    }

    func setDateRange(start: String?, end: String?) {
        filters.startDate = start
        filters.endDate = end
    }

    func setSelected(categoryIds: [String]) { filters.categoryIds = categoryIds }
    func setSelected(payeeIds: [String]) { filters.payeeIds = payeeIds }
    func setSelected(groupIds: [String]) { filters.groupIds = groupIds }

    /// RN `clearFilters` — clears everything including the search text.
    func clearFilters() {
        filters = TransactionService.Filters()
    }

    // MARK: - Loading

    @MainActor
    func load(pool: DatabasePool?, userId: String?) async {
        guard let pool, let userId else {
            page = TransactionService.ListPage()
            errorMessage = nil
            isLoading = false
            return
        }

        isLoading = true
        defer { isLoading = false }

        let filters = filters
        do {
            page = try await pool.read { db in
                try TransactionService.list(userId: userId, filters: filters, in: db)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Categories/payees/groups for the filter popovers and the editor pickers.
    @MainActor
    func loadLookups(pool: DatabasePool?, userId: String?) async {
        guard let pool, let userId else {
            lookups = .empty
            return
        }
        do {
            lookups = try await pool.read { db in
                try TransactionService.lookups(userId: userId, in: db)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func loadStatistics(pool: DatabasePool?, userId: String?) async {
        guard let pool, let userId else {
            statistics = []
            return
        }

        isLoadingStatistics = true
        defer { isLoadingStatistics = false }

        let filters = filters
        do {
            statistics = try await pool.read { db in
                try TransactionService.monthlyStatistics(userId: userId, filters: filters, in: db)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Soft delete (`deleted = 1, sync_status = 1`), then reload. Returns whether
    /// the row was actually updated.
    @MainActor
    func delete(
        _ transaction: Transaction,
        pool: DatabasePool?,
        userId: String?
    ) async -> Bool {
        guard let pool, let userId else { return false }
        do {
            let changed = try await pool.write { db in
                try TransactionService.softDelete(id: transaction.id, userId: userId, in: db)
            }
            await load(pool: pool, userId: userId)
            return changed > 0
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
