import Foundation

/// Reports another section can open directly.
///
/// Phase 6 only needs the three the dashboard links to; Phase 10 grows this into
/// the full index of eleven reports (MACOS_FEATURE_MATRIX.md §7).
enum ReportDestination: String, Identifiable, CaseIterable {
    case monthlySummary
    case yearlySummary
    case summaryByCategory

    var id: String { rawValue }

    /// Matches the `title` param the RN dashboard passes on `router.push`.
    var title: String {
        switch self {
        case .monthlySummary: return "Monthly Summary"
        case .yearlySummary: return "Yearly Summary"
        case .summaryByCategory: return "Transactions By Category"
        }
    }

    /// Matches the `reportType` param the RN dashboard passes on `router.push`.
    var reportType: String {
        switch self {
        case .monthlySummary: return "monthlySummary"
        case .yearlySummary: return "yearlySummary"
        case .summaryByCategory: return "summaryByCategory"
        }
    }
}
