import Foundation

/// Shared display formatting helpers.
///
/// Ports `src/utils/formatters.ts` and the date patterns the React Native
/// dashboard uses with date-fns (DATA_ARCHITECTURE.md §2).
enum AppFormat {
    // MARK: - Currency (₹, en-IN)

    /// Mirrors `formatCurrency`: prefixes `APP_CONFIG.CURRENCY_SYMBOL` (₹) to the
    /// **absolute value** with Indian digit grouping (`en-IN`), 0 fraction digits
    /// when the amount is a whole number and exactly 2 otherwise.
    ///
    /// Note the source helper drops the sign — negative amounts render as their
    /// magnitude and callers convey direction with colour. Preserved deliberately.
    static func currency(_ amount: Double) -> String {
        let isWholeNumber = amount.truncatingRemainder(dividingBy: 1) == 0
        let formatter = isWholeNumber ? wholeNumberCurrency : decimalCurrency
        let text = formatter.string(from: NSNumber(value: abs(amount))) ?? "0"
        return "₹" + text
    }

    private static let wholeNumberCurrency = makeCurrencyFormatter(minimumFractionDigits: 0)
    private static let decimalCurrency = makeCurrencyFormatter(minimumFractionDigits: 2)

    private static func makeCurrencyFormatter(minimumFractionDigits: Int) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en-IN")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = minimumFractionDigits
        formatter.maximumFractionDigits = 2
        return formatter
    }

    // MARK: - Dates

    /// `yyyy-MM-dd`, the format of the `transactions.date` column.
    static func yearMonthDay(_ date: Date, calendar: Calendar = .current) -> String {
        format(date, "yyyy-MM-dd", calendar: calendar)
    }

    /// Full English month name (`MMMM`), e.g. the "THIS MONTH" card subtitle.
    static func monthName(_ date: Date, calendar: Calendar = .current) -> String {
        format(date, "MMMM", calendar: calendar)
    }

    /// Four-digit year (`yyyy`), e.g. the "THIS YEAR" card subtitle.
    static func year(_ date: Date, calendar: Calendar = .current) -> String {
        format(date, "yyyy", calendar: calendar)
    }

    /// RN `formatDate(date, 'MMM dd, yyyy')` → "Sep 21, 2026" (transaction day headers).
    static func monthDayYear(_ dateString: String, calendar: Calendar = .current) -> String {
        formattedDay(dateString, pattern: "MMM dd, yyyy", calendar: calendar)
    }

    /// RN `formatDate(date, 'dd MMM')` → "21 Sep" (the filter summary text).
    static func dayMonth(_ dateString: String, calendar: Calendar = .current) -> String {
        formattedDay(dateString, pattern: "dd MMM", calendar: calendar)
    }

    /// Parses a `yyyy-MM-dd` column value into a date in the calendar's zone.
    static func date(fromYearMonthDay dateString: String, calendar: Calendar = .current) -> Date? {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = calendar.timeZone
        parser.dateFormat = "yyyy-MM-dd"
        return parser.date(from: dateString)
    }

    /// Parses a `yyyy-MM-dd` column value and formats it in the same zone, so the
    /// calendar day can never shift.
    private static func formattedDay(
        _ dateString: String,
        pattern: String,
        calendar: Calendar
    ) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = calendar.timeZone
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: dateString) else { return dateString }
        return format(date, pattern, calendar: calendar)
    }

    /// date-fns `PPp` — the transaction row meta, e.g. "Sep 21, 2026, 9:00 AM".
    static func preciseTimestamp(_ raw: String, timeZone: TimeZone = .current) -> String {
        guard let instant = TransactionTimestamp.instant(from: raw, timeZone: timeZone) else {
            return raw
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = timeZone
        formatter.calendar = gregorian
        formatter.timeZone = timeZone
        formatter.dateFormat = "MMM d, yyyy, h:mm a"
        return formatter.string(from: instant)
    }

    /// date-fns-compatible pattern formatting. Always Gregorian and English so
    /// results match the React Native app regardless of the user's locale.
    static func format(_ date: Date, _ pattern: String, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        formatter.calendar = gregorian
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    // MARK: - Relative time

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.dateTimeStyle = .named
        return formatter
    }()

    /// "5 min. ago", "yesterday", or "Never" when nothing has synced yet.
    static func relativeTime(_ date: Date?) -> String {
        guard let date else { return "Never" }
        return relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}
