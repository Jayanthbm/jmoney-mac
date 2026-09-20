import XCTest

@testable import Jmoney

/// Verifies the Swift port of `src/utils/transactionTimestamp.ts` is
/// byte-compatible with the JavaScript semantics (DATA_ARCHITECTURE.md §2).
final class TimestampRuleTests: XCTestCase {
    private let kolkata = TimeZone(identifier: "Asia/Kolkata")! // UTC+05:30, no DST
    private let utc = TimeZone(identifier: "UTC")!
    private let newYork = TimeZone(identifier: "America/New_York")!

    // MARK: toSupabaseFormat

    func testSuffixedUTCTimestampBecomesLocalWallClock() {
        // 10:30 UTC + 05:30 = 16:00 IST, same calendar day.
        XCTAssertEqual(
            TransactionTimestamp.toSupabaseFormat("2026-09-20T10:30:00.000Z", timeZone: kolkata),
            "2026-09-20T16:00:00.000"
        )
    }

    func testSuffixedTimestampCrossingMidnightMovesDate() {
        // 20:30 UTC + 05:30 = 02:00 IST the next day.
        XCTAssertEqual(
            TransactionTimestamp.toSupabaseFormat("2026-09-20T20:30:00.000Z", timeZone: kolkata),
            "2026-09-21T02:00:00.000"
        )
    }

    func testOffsetSuffixConvertsToTargetZone() {
        XCTAssertEqual(
            TransactionTimestamp.toSupabaseFormat("2026-09-20T10:30:00.000+02:00", timeZone: utc),
            "2026-09-20T08:30:00.000"
        )
    }

    func testOffsetSuffixWithoutColonIsAccepted() {
        // JS `new Date` accepts `+0200`; the port normalizes it.
        XCTAssertEqual(
            TransactionTimestamp.toSupabaseFormat("2026-09-20T10:30:00+0200", timeZone: utc),
            "2026-09-20T08:30:00.000"
        )
    }

    func testSuffixlessTimestampKeepsRawClockReplacingFirstSpaceOnly() {
        // JS `.replace(' ', 'T')` replaces only the first space.
        XCTAssertEqual(
            TransactionTimestamp.toSupabaseFormat("2026-09-20 10:30:00.000 12:00", timeZone: utc),
            "2026-09-20T10:30:00.000 12:00"
        )
        XCTAssertEqual(
            TransactionTimestamp.toSupabaseFormat("2026-09-20T10:30:00.000", timeZone: utc),
            "2026-09-20T10:30:00.000"
        )
    }

    func testUnparseableTimestampReturnsUnchanged() {
        XCTAssertEqual(
            TransactionTimestamp.toSupabaseFormat("not-a-date", timeZone: utc),
            "not-a-date"
        )
    }

    func testLowercaseZSuffixIsAccepted() {
        XCTAssertEqual(
            TransactionTimestamp.toSupabaseFormat("2026-09-20t10:30:00.000z", timeZone: utc),
            "2026-09-20T10:30:00.000"
        )
    }

    // MARK: day(from:)

    func testDayExtractsPrefixWithoutTimezoneConversion() {
        // The raw string prefix is used — no conversion, any zone.
        XCTAssertEqual(
            TransactionTimestamp.day(from: "2026-09-20T23:30:00.000Z", timeZone: newYork),
            "2026-09-20"
        )
        XCTAssertEqual(
            TransactionTimestamp.day(from: "2026-09-20 23:30:00", timeZone: newYork),
            "2026-09-20"
        )
    }

    func testDayFallsBackToPrefixBeforeFirstTWhenUnparseable() {
        // JS `timestamp.split('T')[0]`.
        XCTAssertEqual(TransactionTimestamp.day(from: "garbage", timeZone: utc), "garbage")
        XCTAssertEqual(TransactionTimestamp.day(from: "abcTdef", timeZone: utc), "abc")
    }

    func testDateOnlyStringParsesAsUTCMidnight() {
        // JS `new Date('2026-09-20')` is UTC midnight; formatting in a
        // negative-offset zone shifts the day. Known cross-device drift quirk
        // documented in DATA_ARCHITECTURE.md §2.
        XCTAssertEqual(
            TransactionTimestamp.day(from: "2026-09-20", timeZone: newYork),
            "2026-09-19"
        )
        XCTAssertEqual(
            TransactionTimestamp.day(from: "2026-09-20", timeZone: utc),
            "2026-09-20"
        )
    }

    func testShortNonPrefixedStringsFallBackGracefully() {
        XCTAssertEqual(TransactionTimestamp.day(from: "", timeZone: utc), "")
        XCTAssertEqual(TransactionTimestamp.day(from: "2026-9-20x", timeZone: utc), "2026-9-20x")
    }
}
