import XCTest

@testable import Jmoney

/// Verifies `AppFormat` against `src/utils/formatters.ts`.
final class FormatterTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    // MARK: - Currency

    func testCurrencyUsesTheRupeeSymbol() {
        XCTAssertEqual(AppFormat.currency(0), "₹0")
        XCTAssertEqual(AppFormat.currency(500), "₹500")
    }

    func testWholeAmountsUseNoFractionDigits() {
        XCTAssertEqual(AppFormat.currency(1234), "₹1,234")
        XCTAssertEqual(AppFormat.currency(100), "₹100")
    }

    func testFractionalAmountsUseExactlyTwoFractionDigits() {
        XCTAssertEqual(AppFormat.currency(1234.5), "₹1,234.50")
        XCTAssertEqual(AppFormat.currency(0.25), "₹0.25")
    }

    func testAmountsUseIndianDigitGrouping() {
        XCTAssertEqual(AppFormat.currency(100_000), "₹1,00,000")
        XCTAssertEqual(AppFormat.currency(1_234_567), "₹12,34,567")
    }

    func testCurrencyDropsTheSign() {
        // Source quirk: `formatCurrency` formats `Math.abs(amount)`, and callers
        // convey direction with colour. Preserved for parity.
        XCTAssertEqual(AppFormat.currency(-50), "₹50")
        XCTAssertEqual(AppFormat.currency(-1_234.5), "₹1,234.50")
    }

    // MARK: - Dates

    func testYearMonthDayUsesTheCalendarTimeZone() {
        XCTAssertEqual(AppFormat.yearMonthDay(date(2026, 9, 21), calendar: calendar), "2026-09-21")
    }

    func testMonthNameAndYearAreEnglish() {
        XCTAssertEqual(AppFormat.monthName(date(2026, 9, 21), calendar: calendar), "September")
        XCTAssertEqual(AppFormat.year(date(2026, 9, 21), calendar: calendar), "2026")
    }

    func testPayDayLabelPattern() {
        XCTAssertEqual(AppFormat.format(date(2026, 10, 1), "MMM 01", calendar: calendar), "Oct 01")
    }

    func testRelativeTimeIsNeverWhenThereIsNoDate() {
        XCTAssertEqual(AppFormat.relativeTime(nil), "Never")
    }
}
