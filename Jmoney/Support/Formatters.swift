import Foundation

/// Shared display formatting helpers.
///
/// Currency (₹, en-IN) and date formatters matching the React Native app's
/// `formatters.ts` arrive with the data layer; only relative time is needed by
/// the shell.
enum AppFormat {
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
