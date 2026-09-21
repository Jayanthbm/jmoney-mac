import Foundation
import GRDB
import Observation

/// Dashboard view model.
///
/// Owns the fetched metrics and the "now" they were computed against, so the
/// daily-limit and pay-day widgets stay consistent with the data on screen.
/// Replaces the RN `useDashboardData` hook (the `module_refreshed` event and the
/// `DeviceEventEmitter` listener have no macOS equivalent — the view re-runs its
/// load when the section appears, and the toolbar Refresh button reloads on demand).
@Observable
final class DashboardViewModel {
    private(set) var metrics = DashboardService.Metrics()
    private(set) var referenceDate = Date()
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    /// `calculateDailyLimit` is re-derived whenever the metrics change, matching
    /// the `useMemo` around it in `useDashboardData`.
    var dailyLimit: DashboardService.DailyLimit {
        DashboardService.calculateDailyLimit(metrics: metrics, now: referenceDate)
    }

    /// `calculatePayDayInfo` — computed once per load (the RN hook memoizes it
    /// with an empty dependency list, so it only reflects the mount time).
    var payDayInfo: DashboardService.PayDay {
        DashboardService.calculatePayDayInfo(now: referenceDate)
    }

    /// Clears a captured load error after it has been surfaced to the user.
    @MainActor
    func clearError() {
        errorMessage = nil
    }

    /// Loads `fetchDashboardMetrics`. With no session or no open pool the metrics
    /// reset to zero values, which is the correct rendering for an empty database.
    @MainActor
    func load(pool: DatabasePool?, userId: String?) async {
        guard let pool, let userId else {
            metrics = DashboardService.Metrics()
            referenceDate = Date()
            errorMessage = nil
            isLoading = false
            return
        }

        isLoading = true
        defer { isLoading = false }

        let now = Date()
        do {
            metrics = try await pool.read { db in
                try DashboardService.fetchMetrics(userId: userId, now: now, in: db)
            }
            referenceDate = now
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
