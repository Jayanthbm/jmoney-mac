import GRDB
import XCTest

@testable import Jmoney

/// Verifies the calendar's queries: the day transaction list (scoping, ordering)
/// and the earliest-transaction bound the grid pages against.
///
/// The day list is `getTransactionsByDate`, which is byte-identical SQL to the
/// dashboard's drill-down, so this also guards the shared implementation.
final class CalendarServiceTests: XCTestCase {
    private let user = "u1"

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func makeSeededDatabase() throws -> DatabaseQueue {
        let dbQueue = try DatabaseQueue()
        try DatabaseService.migrator.migrate(dbQueue)
        try dbQueue.write { db in try seed(db) }
        return dbQueue
    }

    private func insertTransaction(
        _ db: Database,
        id: String,
        amount: Double,
        type: String,
        date: String,
        timestamp: String,
        userId: String? = nil,
        deleted: Int = 0
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO transactions
                    (id, amount, type, date, transaction_timestamp, description, user_id,
                     deleted, sync_status, tid, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, '', ?, ?, 0, 0, ?, ?)
                """,
            arguments: [
                id, amount, type, date, timestamp, userId ?? self.user, deleted,
                "2026-09-21T00:00:00.000Z", "2026-09-21T00:00:00.000Z",
            ]
        )
    }

    /// Three rows on 21 September 2026 (deliberately out of timestamp order in the
    /// fixture), one on the 20th, one on an earlier month, plus noise.
    private func seed(_ db: Database) throws {
        try insertTransaction(
            db, id: "t-income", amount: 5000, type: "Income", date: "2026-09-21",
            timestamp: "2026-09-21T09:00:00.000Z"
        )
        try insertTransaction(
            db, id: "t-food", amount: 1300, type: "Expense", date: "2026-09-21",
            timestamp: "2026-09-21T18:30:00.000Z"
        )
        try insertTransaction(
            db, id: "t-fun", amount: 300, type: "Expense", date: "2026-09-21",
            timestamp: "2026-09-21T12:00:00.000Z"
        )

        try insertTransaction(
            db, id: "t-yesterday", amount: 200, type: "Expense", date: "2026-09-20",
            timestamp: "2026-09-20T12:00:00.000Z"
        )

        try insertTransaction(
            db, id: "t-august", amount: 800, type: "Expense", date: "2026-08-05",
            timestamp: "2026-08-05T12:00:00.000Z"
        )

        // Noise that must never appear.
        try insertTransaction(
            db, id: "t-deleted", amount: 999, type: "Expense", date: "2026-09-21",
            timestamp: "2026-09-21T20:00:00.000Z", deleted: 1
        )
        try insertTransaction(
            db, id: "t-other-user", amount: 999, type: "Expense", date: "2026-09-21",
            timestamp: "2026-09-21T21:00:00.000Z", userId: "u2"
        )
    }

    private func dayTransactions(_ dbQueue: DatabaseQueue, _ day: Date) throws -> [Transaction] {
        try dbQueue.read { db in
            try CalendarService.transactions(
                userId: self.user, date: day, calendar: self.calendar, in: db
            )
        }
    }

    // MARK: - Day list

    func testTheDayListIsScopedToTheUserAndTheDay() throws {
        let dbQueue = try makeSeededDatabase()
        let rows = try dayTransactions(dbQueue, date(2026, 9, 21))

        XCTAssertEqual(Set(rows.map(\.id)), ["t-income", "t-food", "t-fun"])
    }

    func testTheDayListIsOrderedByTimestampNewestFirst() throws {
        let dbQueue = try makeSeededDatabase()
        let rows = try dayTransactions(dbQueue, date(2026, 9, 21))

        XCTAssertEqual(rows.map(\.id), ["t-food", "t-fun", "t-income"])
    }

    func testAnotherDayIsSeparate() throws {
        let dbQueue = try makeSeededDatabase()

        XCTAssertEqual(try dayTransactions(dbQueue, date(2026, 9, 20)).map(\.id), ["t-yesterday"])
        XCTAssertEqual(try dayTransactions(dbQueue, date(2026, 8, 5)).map(\.id), ["t-august"])
    }

    func testADayWithNoActivityIsEmpty() throws {
        let dbQueue = try makeSeededDatabase()

        XCTAssertTrue(try dayTransactions(dbQueue, date(2026, 9, 15)).isEmpty)
    }

    /// The column value is formatted from the date in the query's calendar, so the
    /// boundary between two days cannot drift: 23:30 local and 00:30 local are
    /// different days even though they are close in UTC.
    func testTheDayBoundaryFollowsTheCalendarZone() throws {
        let dbQueue = try makeSeededDatabase()

        let lateNight = date(2026, 9, 21, hour: 23)
        let nextMorning = date(2026, 9, 22, hour: 1)

        XCTAssertEqual(try dayTransactions(dbQueue, lateNight).count, 3)
        XCTAssertTrue(try dayTransactions(dbQueue, nextMorning).isEmpty)
    }

    // MARK: - Earliest transaction bound

    func testTheEarliestTransactionDateIsTheOldestRow() throws {
        let dbQueue = try makeSeededDatabase()

        let minimum = try dbQueue.read { db in
            try CalendarService.minDate(
                userId: self.user, now: self.date(2026, 9, 21), calendar: self.calendar, in: db
            )
        }

        XCTAssertEqual(AppFormat.yearMonthDay(minimum, calendar: calendar), "2026-08-05")
    }

    /// `getMinTransactionDate` falls back to today, so a fresh account has no
    /// navigable history.
    func testAnEmptyLedgerFallsBackToToday() throws {
        let dbQueue = try makeSeededDatabase()

        let minimum = try dbQueue.read { db in
            try CalendarService.minDate(
                userId: "u-empty", now: self.date(2026, 9, 21), calendar: self.calendar, in: db
            )
        }

        XCTAssertEqual(AppFormat.yearMonthDay(minimum, calendar: calendar), "2026-09-21")
    }

    func testADeletedRowDoesNotMoveTheBoundBackwards() throws {
        let dbQueue = try makeSeededDatabase()
        try dbQueue.write { db in
            try insertTransaction(
                db, id: "t-old", amount: 10, type: "Expense", date: "2020-01-01",
                timestamp: "2020-01-01T12:00:00.000Z", deleted: 1
            )
        }

        let minimum = try dbQueue.read { db in
            try CalendarService.minDate(
                userId: self.user, now: self.date(2026, 9, 21), calendar: self.calendar, in: db
            )
        }

        XCTAssertEqual(AppFormat.yearMonthDay(minimum, calendar: calendar), "2026-08-05")
    }

    /// The shared query is the one the budgets and reports screens page against,
    /// so the calendar's bound and theirs must agree.
    func testTheBoundAgreesWithTheBudgetsAndReportsPort() throws {
        let dbQueue = try makeSeededDatabase()

        let (fromBudget, fromReports, fromCalendar) = try dbQueue.read { db in
            (
                try BudgetService.minTransactionDate(userId: self.user, in: db),
                try TransactionBounds.minDate(userId: self.user, in: db),
                try CalendarService.minDate(userId: self.user, in: db)
            )
        }

        XCTAssertEqual(
            AppFormat.yearMonthDay(fromBudget, calendar: calendar),
            AppFormat.yearMonthDay(fromReports, calendar: calendar)
        )
        XCTAssertEqual(
            AppFormat.yearMonthDay(fromBudget, calendar: calendar),
            AppFormat.yearMonthDay(fromCalendar, calendar: calendar)
        )
    }
}
