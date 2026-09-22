import Foundation

/// A daily-reminder choice.
///
/// Ports the `notification_pref` handling of `app/(tabs)/settings/index.tsx`,
/// `src/hooks/useAppSettings.ts` and `src/services/notificationService.ts`.
///
/// Stored values are the source's own strings: `"None"`, `"Morning"`,
/// `"Evening"`, `"Night"`, or a custom `"HH:mm"`. Note that the source *removes*
/// the key when the choice is `None` (`scheduleReminder` calls `removeItem`), so
/// "no reminder" and "never configured" are the same stored state — both read
/// back as `.none`.
enum ReminderPreference: Equatable {
    case none
    case morning
    case evening
    case night
    /// A stored custom value. Carries the raw string rather than parsed
    /// components because the source can hold arbitrary text here (see
    /// `scheduleTime` and `isCustomChoice`).
    case custom(String)

    /// The key the source uses.
    static let storageKey = "notification_pref"

    /// The four named rows of the source's chooser sheet, in its order. The Custom
    /// row is not a case here — it is the absence of one of these four.
    enum NamedChoice: String, CaseIterable, Identifiable, Equatable {
        case none = "None"
        case morning = "Morning"
        case evening = "Evening"
        case night = "Night"

        var id: String { rawValue }

        var title: String { rawValue }

        /// The source's `item.time` subtitle ("9:00 AM", …); `None` has none.
        var detail: String? {
            switch self {
            case .none: return nil
            case .morning: return "9:00 AM"
            case .evening: return "6:00 PM"
            case .night: return "9:00 PM"
            }
        }

        var systemImage: String {
            switch self {
            case .none: return "bell.slash"
            case .morning, .evening, .night: return "clock"
            }
        }

        var preference: ReminderPreference {
            switch self {
            case .none: return .none
            case .morning: return .morning
            case .evening: return .evening
            case .night: return .night
            }
        }
    }

    // MARK: - Storage

    /// The literal the source writes for this choice.
    var storageValue: String {
        switch self {
        case .none: return "None"
        case .morning: return "Morning"
        case .evening: return "Evening"
        case .night: return "Night"
        case .custom(let raw): return raw
        }
    }

    /// `notificationPref` as the settings screen reads it. An absent key leaves
    /// the screen's initial `"None"` in place, and anything that is not one of the
    /// four names is treated as a custom value — the source's
    /// `notificationPref.includes(':')` test only decides which *row* is shown as
    /// selected, never how the value is loaded.
    static func stored(in defaults: UserDefaults = .standard) -> ReminderPreference {
        guard let raw = defaults.string(forKey: storageKey), !raw.isEmpty else { return .none }
        return parse(raw)
    }

    /// Splits a raw stored string into a choice.
    static func parse(_ raw: String) -> ReminderPreference {
        switch raw {
        case "None": return .none
        case "Morning": return .morning
        case "Evening": return .evening
        case "Night": return .night
        default: return .custom(raw)
        }
    }

    /// `AsyncStorage.setItem('notification_pref', …)`. `None` removes the key,
    /// which is the source's end state after `scheduleReminder('None')`.
    static func save(_ preference: ReminderPreference, in defaults: UserDefaults = .standard) {
        if preference == .none {
            defaults.removeObject(forKey: storageKey)
        } else {
            defaults.set(preference.storageValue, forKey: storageKey)
        }
    }

    // MARK: - Display

    /// The settings row's value text.
    ///
    /// `notificationPref === 'None' ? 'Off' : … : \`Custom (${formatTime(…)})\``.
    var displayValue: String {
        switch self {
        case .none: return "Off"
        case .morning: return "Morning (9:00 AM)"
        case .evening: return "Evening (6:00 PM)"
        case .night: return "Night (9:00 PM)"
        case .custom(let raw): return "Custom (\(Self.formattedTime(raw)))"
        }
    }

    /// The custom row's subtitle: the chosen time, or the source's
    /// `'Select Time'` placeholder.
    var customDetail: String {
        isCustomChoice ? Self.formattedTime(storageValue) : "Select Time"
    }

    /// `isCustom = notificationPref.includes(':')` — the source's test for whether
    /// the Custom row reads as selected. A stored value with no colon (which the
    /// app itself never writes, but an older build could have) leaves *no* row
    /// selected while still displaying as `Custom (…)`.
    var isCustomChoice: Bool {
        if case .custom(let raw) = self { return raw.contains(":") }
        return false
    }

    /// Whether a named row is the selected one, following the source's
    /// `notificationPref === item.label` comparison.
    func selects(_ choice: NamedChoice) -> Bool {
        self == choice.preference
    }

    /// `formatTime` — `"18:30"` → `"6:30 PM"`. A string without a colon is
    /// returned unchanged, exactly as the source does.
    static func formattedTime(_ raw: String) -> String {
        guard let time = Self.splitClock(raw) else { return raw }
        let suffix = time.hour >= 12 ? "PM" : "AM"
        let hour12 = time.hour % 12 == 0 ? 12 : time.hour % 12
        return "\(hour12):\(String(format: "%02d", time.minute)) \(suffix)"
    }

    // MARK: - Scheduling

    /// The trigger time, or `nil` when nothing should be scheduled.
    ///
    /// Reproduces `scheduleReminder`'s branch structure, including its default:
    /// only `Evening`, `Night` and a colon-bearing custom value set the hour, so
    /// `Morning` — and any other unrecognized value — falls through to the 9:00
    /// default.
    var scheduleTime: (hour: Int, minute: Int)? {
        switch self {
        case .none: return nil
        case .morning: return (9, 0)
        case .evening: return (18, 0)
        case .night: return (21, 0)
        case .custom(let raw):
            // `Morning` and any unrecognized value share this default branch in
            // the source, so a value with no parseable hour also lands at 9:00.
            return Self.splitClock(raw) ?? (9, 0)
        }
    }

    /// Splits a `"H:mm"` / `"HH:mm"` value into its clock components.
    ///
    /// Returns `nil` when the value has no colon or no numeric hour — the cases
    /// where the source leaves `hour`/`minute` at their 9:00 defaults. Guards
    /// against degenerate values (`":"`, `"abc"`) instead of indexing blindly.
    private static func splitClock(_ raw: String) -> (hour: Int, minute: Int)? {
        guard raw.contains(":") else { return nil }
        let parts = raw.split(separator: ":")
        guard let first = parts.first, let hour = Int(first) else { return nil }
        let minute = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        return (hour, minute)
    }
}
