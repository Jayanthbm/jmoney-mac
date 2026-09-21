import SwiftUI

/// The report catalog — the eleven entries of `reportsList` in
/// `app/(tabs)/reports/index.tsx`, and the report types `reportService.ts`
/// switches on.
///
/// The `rawValue` is the source's `view` / `reportType` string, so the RN
/// vocabulary is preserved; the behavioural flags below are the per-screen
/// `ReportSelectors` props (which reports show a type toggle, a month, a
/// comparison column, a search field) gathered in one place instead of being
/// repeated across eleven near-identical screens.
///
/// `yearlyGroup` is deliberately absent: `fetchReportData` and
/// `handleReportDrillDown` handle it, and `getReportYearlySummaryByGroup` is
/// ported by `ReportService`, but no entry in the RN index reaches it — there is
/// no `app/reports/yearly-group.tsx`. Its behaviour is covered by the service
/// tests rather than left as dead UI.
enum ReportDestination: String, Identifiable, CaseIterable {
    case groups
    case monthlyLivingCosts
    case subscriptionAndBills
    case summaryByPayee
    case summaryByCategory
    case monthlySummary
    case yearlySummary
    case transactionsByYear
    case yearlyPayees
    case payees
    case categories

    var id: String { rawValue }

    /// The RN index's `title`, also what `router.push` passes as `title`.
    var title: String {
        switch self {
        case .groups: return "Transactions By Group"
        case .monthlyLivingCosts: return "Monthly Living Costs"
        case .subscriptionAndBills: return "Subscription and Bills"
        case .summaryByPayee: return "Transactions By Payee"
        case .summaryByCategory: return "Transactions By Category"
        case .monthlySummary: return "Monthly Summary"
        case .yearlySummary: return "Yearly Summary"
        case .transactionsByYear: return "Transactions By Year"
        case .yearlyPayees: return "Yearly Payees"
        case .payees: return "Payees"
        case .categories: return "Categories"
        }
    }

    /// The RN index's `description`.
    var summary: String {
        switch self {
        case .groups: return "History by group"
        case .monthlyLivingCosts: return "Essential monthly expenses"
        case .subscriptionAndBills: return "Recurring payments"
        case .summaryByPayee: return "History by payee"
        case .summaryByCategory: return "History by category"
        case .monthlySummary: return "Monthly performance"
        case .yearlySummary: return "Yearly performance"
        case .transactionsByYear: return "Yearly history by category"
        case .yearlyPayees: return "Yearly history by payee"
        case .payees: return "Overall payee analysis"
        case .categories: return "Overall category analysis"
        }
    }

    /// The RN index icons (`MaterialIcons`) as SF Symbols. Material→SF Symbol
    /// mapping for *category* icons is Phase 12's job; these are report glyphs.
    var icon: String {
        switch self {
        case .groups: return "folder"
        case .monthlyLivingCosts: return "house"
        case .subscriptionAndBills: return "arrow.triangle.2.circlepath"
        case .summaryByPayee: return "person"
        case .summaryByCategory: return "square.grid.2x2"
        case .monthlySummary: return "calendar"
        case .yearlySummary: return "calendar.badge.clock"
        case .transactionsByYear: return "chart.bar"
        case .yearlyPayees: return "person.2"
        case .payees: return "person.2"
        case .categories: return "square.grid.2x2"
        }
    }

    /// The RN index accent colours, kept as-is so the index reads the same.
    var color: Color {
        switch self {
        case .groups: return Color(hex: 0x8B5CF6)
        case .monthlyLivingCosts: return Color(hex: 0x6366F1)
        case .subscriptionAndBills: return Color(hex: 0xEC4899)
        case .summaryByPayee: return Color(hex: 0xF59E0B)
        case .summaryByCategory: return Color(hex: 0x10B981)
        case .monthlySummary: return Color(hex: 0x3B82F6)
        case .yearlySummary: return Color(hex: 0xEF4444)
        case .transactionsByYear: return Color(hex: 0x8B5CF6)
        case .yearlyPayees: return Color(hex: 0x3B82F6)
        case .payees: return Color(hex: 0x06B6D4)
        case .categories: return Color(hex: 0xF43F5E)
        }
    }

    // MARK: - Behaviour flags (the RN per-screen `ReportSelectors` props)

    /// `reportType` in `reportService.ts`'s `comparisonTypes`.
    var supportsComparison: Bool {
        switch self {
        case .summaryByPayee, .summaryByCategory, .monthlyLivingCosts,
             .subscriptionAndBills, .monthlySummary, .yearlySummary,
             .transactionsByYear, .yearlyPayees:
            return true
        case .groups, .payees, .categories:
            return false
        }
    }

    /// `useReportData`'s `isYearly`: period stepping moves a year at a time and
    /// the comparison compares years.
    var isYearly: Bool {
        switch self {
        case .yearlySummary, .transactionsByYear, .yearlyPayees: return true
        default: return false
        }
    }

    /// `['monthlySummary', 'yearlySummary'].includes(reportType)` — the reports
    /// that render the four-metric grid instead of a total banner and rows.
    var isSummary: Bool {
        self == .monthlySummary || self == .yearlySummary
    }

    /// The RN screens pass `showTypeToggle` — Expense/Income segmented control.
    var hasTypeToggle: Bool {
        switch self {
        case .monthlySummary, .yearlySummary, .monthlyLivingCosts,
             .subscriptionAndBills:
            return false
        default:
            return true
        }
    }

    /// The RN screens pass `showMonthSelector`.
    var showsMonth: Bool {
        switch self {
        case .groups, .yearlySummary, .transactionsByYear, .yearlyPayees,
             .payees, .categories:
            return false
        default:
            return true
        }
    }

    /// The RN screens pass `showYearSelector`.
    var showsYear: Bool {
        self != .groups && self != .payees && self != .categories
    }

    /// `payees` / `categories` — the two overview screens, which are the only
    /// ones with a search field and a sort picker.
    var isOverview: Bool {
        self == .payees || self == .categories
    }

    /// The `yearlySummary` label difference in the comparison toggle.
    var comparisonToggleTitle: String {
        isYearly ? "Full Year" : "Full Month"
    }

    /// What "Back to Current …" says — the RN selector uses the *is-yearly set*
    /// ({yearlySummary, transactionsByYear, yearlyPayees}), not `isYearly`.
    var backToCurrentTitle: String {
        isYearly ? "Back to Current Year" : "Back to Current Month"
    }

    /// `summaryByCategory`, `monthlyLivingCosts`, `categories` and
    /// `transactionsByYear` drill down by category name.
    var drillsDownByCategory: Bool {
        switch self {
        case .summaryByCategory, .monthlyLivingCosts, .categories, .transactionsByYear:
            return true
        default:
            return false
        }
    }

    /// The dashboard's `ReportDestination` click-through uses these three.
    static var dashboardLinks: [ReportDestination] {
        [.summaryByCategory, .monthlySummary, .yearlySummary]
    }
}

extension Color {
    /// The RN index colours are hex literals; this keeps them readable above.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
