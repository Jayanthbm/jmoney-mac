import Foundation

/// Ports of the timestamp rules in the React Native app's
/// `src/utils/transactionTimestamp.ts`. Semantics must stay byte-compatible to
/// avoid cross-device date drift (DATA_ARCHITECTURE.md §2 "Timestamps" and §7).
///
/// `timeZone` defaults to `.current` (the JS functions use the device's local
/// time); tests pass fixed zones for deterministic assertions.
enum TransactionTimestamp {
    /// `(Z|[+-]\d{2}:?\d{2})$` — case-insensitive, from `timezoneSuffixPattern`.
    private static let timezoneSuffixRegex = try! NSRegularExpression(
        pattern: "(Z|[+-]\\d{2}:?\\d{2})$",
        options: [.caseInsensitive]
    )

    // MARK: toSupabaseTransactionTimestamp

    /// Push format: local wall-clock without a timezone suffix.
    ///
    /// - No suffix: replaces the first space with `T` (JS `.replace(' ', 'T')`
    ///   replaces only the first occurrence) and returns as-is otherwise.
    /// - Suffix: converts to the device's local wall-clock — this is how UTC
    ///   timestamps saved by `date.toISOString()` become local on push.
    static func toSupabaseFormat(_ timestamp: String, timeZone: TimeZone = .current) -> String {
        guard hasTimezoneSuffix(timestamp) else {
            return replacingFirstSpace(withT: timestamp)
        }
        guard let date = parse(timestamp) else { return timestamp }
        return wallClockString(from: date, timeZone: timeZone)
    }

    // MARK: getTransactionDate

    /// The `yyyy-MM-dd` day for a timestamp.
    ///
    /// - If the string starts with a date followed by `T` or a space, the raw
    ///   prefix is returned untouched (no timezone conversion).
    /// - Otherwise JS `new Date` parsing is attempted; unparseable strings
    ///   fall back to the part before the first `T`.
    static func day(from timestamp: String, timeZone: TimeZone = .current) -> String {
        if let prefix = datePrefix(timestamp) {
            return prefix
        }
        guard let date = parse(timestamp) else {
            return String(
                timestamp.split(separator: "T", maxSplits: 1, omittingEmptySubsequences: false)[0]
            )
        }
        return dayString(from: date, timeZone: timeZone)
    }

    // MARK: instant

    /// A sortable instant for a stored `transaction_timestamp`, mirroring the
    /// JavaScript `new Date(ts).getTime()` that `mapTransactionsToFlashList`
    /// sorts by. Returns nil when the string cannot be parsed, so callers can
    /// fall back to a plain string comparison.
    ///
    /// Rows written by the sync pull hold a *local* wall-clock string with no
    /// suffix (see `toSupabaseFormat`); JS parses those as local time, so the
    /// same fallback is applied here.
    static func instant(from timestamp: String, timeZone: TimeZone = .current) -> Date? {
        if let date = parse(timestamp) { return date }
        let candidate = replacingFirstSpace(withT: timestamp)
        if let date = localWallClockFormatter(precision: "yyyy-MM-dd'T'HH:mm:ss.SSS", timeZone: timeZone)
            .date(from: candidate) {
            return date
        }
        return localWallClockFormatter(precision: "yyyy-MM-dd'T'HH:mm:ss", timeZone: timeZone)
            .date(from: candidate)
    }

    // MARK: utcISOString

    /// JavaScript `date.toISOString()` — UTC with a `Z` suffix and exactly three
    /// fraction digits, which is how `transaction_timestamp` is written on save.
    static func utcISOString(from date: Date) -> String {
        isoFormatterWithFraction.string(from: date)
    }

    // MARK: - Pattern helpers

    private static func hasTimezoneSuffix(_ timestamp: String) -> Bool {
        let range = NSRange(timestamp.startIndex..., in: timestamp)
        return timezoneSuffixRegex.firstMatch(in: timestamp, options: [], range: range) != nil
    }

    private static func replacingFirstSpace(withT timestamp: String) -> String {
        guard let spaceRange = timestamp.range(of: " ") else { return timestamp }
        return timestamp.replacingCharacters(in: spaceRange, with: "T")
    }

    /// Matches `^(\d{4}-\d{2}-\d{2})[T ]` and returns the 10-character date.
    private static func datePrefix(_ timestamp: String) -> String? {
        let chars = Array(timestamp)
        guard chars.count >= 11 else { return nil }

        func isDigit(_ c: Character) -> Bool { c.isNumber && c.isASCII }
        let digitsAt: [Int] = [0, 1, 2, 3, 5, 6, 8, 9]
        for index in digitsAt where !isDigit(chars[index]) { return nil }
        guard chars[4] == "-", chars[7] == "-" else { return nil }
        guard chars[10] == "T" || chars[10] == " " else { return nil }

        return String(chars[0...9])
    }

    // MARK: - Parsing (mirrors JavaScript `new Date(string)`)

    private static func parse(_ timestamp: String) -> Date? {
        var candidate = timestamp

        // ECMAScript's date-time format accepts a lowercase separator `t` and
        // trailing `z`; ISO8601DateFormatter requires uppercase, so normalize
        // exactly those markers.
        candidate = normalizingCaseInsensitiveISOMarkers(candidate)

        // JS accepts offsets without a colon (`+0200`); normalize to `+02:00`.
        let range = NSRange(candidate.startIndex..., in: candidate)
        if let match = timezoneSuffixRegex.firstMatch(in: candidate, options: [], range: range),
           match.range.length == 5,
           let matchRange = Range(match.range, in: candidate) {
            let suffix = candidate[matchRange]
            if suffix.first == "+" || suffix.first == "-" {
                candidate.insert(":", at: candidate.index(matchRange.upperBound, offsetBy: -2))
            }
        }

        if let date = isoFormatterWithFraction.date(from: candidate) { return date }
        if let date = isoFormatter.date(from: candidate) { return date }

        // JS parses date-only strings (`2026-09-20`) as UTC midnight.
        if let date = dateOnlyFormatter.date(from: candidate) { return date }

        return nil
    }

    private static func normalizingCaseInsensitiveISOMarkers(_ string: String) -> String {
        var chars = Array(string)
        if chars.count >= 11, chars[10] == "t" {
            chars[10] = "T"
        }
        if let last = chars.last, last == "z" {
            chars[chars.count - 1] = "Z"
        }
        return String(chars)
    }

    // MARK: - Formatting

    private static func wallClockString(from date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        return formatter.string(from: date)
    }

    private static func dayString(from date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func localWallClockFormatter(precision: String, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = precision
        return formatter
    }

    private static let isoFormatterWithFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFormatter = ISO8601DateFormatter()

    private static let dateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
