import Foundation
import GRDB

/// Bounds derived from the transaction ledger.
///
/// `SELECT MIN(date) FROM transactions WHERE user_id = ? AND deleted = 0` is the
/// source's `getMinTransactionDate`, and three screens need it: budgets and
/// reports use it as the earliest month they can page back to, and the calendar
/// as the earliest month its grid may show. Keeping one implementation avoids
/// three subtly different fallbacks.
///
/// The RN fallback is `format(new Date(), 'yyyy-MM-dd')` — today — so a fresh
/// account cannot page backwards at all.
enum TransactionBounds {
    /// The earliest non-deleted transaction date, or `now` when there is no
    /// history.
    ///
    /// Note the source parses its `yyyy-MM-dd` column value with
    /// `new Date('2024-01-15')`, which JS reads as **UTC midnight**; the value is
    /// parsed in the supplied calendar's zone here, like every other date in the
    /// port, so the earliest month cannot shift by a day in a negative-offset
    /// time zone.
    static func minDate(
        userId: String,
        now: Date = Date(),
        calendar: Calendar = .current,
        in db: Database
    ) throws -> Date {
        let row = try Row.fetchOne(
            db,
            sql: "SELECT MIN(date) as min_date FROM transactions WHERE user_id = ? AND deleted = 0",
            arguments: [userId]
        )
        guard let raw: String = row?["min_date"], !raw.isEmpty else { return now }
        return AppFormat.date(fromYearMonthDay: raw, calendar: calendar) ?? now
    }
}
