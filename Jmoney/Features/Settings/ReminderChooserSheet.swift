import SwiftUI

/// The daily-reminder chooser.
///
/// Ports the "Choose Reminder" bottom sheet in `app/(tabs)/settings/index.tsx`:
/// the same five rows in the same order, the same subtitles (`9:00 AM`,
/// `6:00 PM`, `9:00 PM`, or the stored custom time), and the same rule for which
/// row reads as selected — the Custom row is selected only when the stored value
/// contains a colon (`ReminderPreference.isCustomChoice`).
///
/// The one interaction change: the source swaps the sheet for a spinner date
/// picker the moment Custom is tapped. Here the custom row expands in place with a
/// time field and an explicit Set button, so the choice can be adjusted before it
/// is committed.
struct ReminderChooserSheet: View {
    let current: ReminderPreference
    let onSelect: (ReminderPreference) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isEditingCustom: Bool
    @State private var customTime: Date

    init(current: ReminderPreference, onSelect: @escaping (ReminderPreference) -> Void) {
        self.current = current
        self.onSelect = onSelect
        let hasCustomTime = current.isCustomChoice
        _isEditingCustom = State(initialValue: hasCustomTime)
        _customTime = State(initialValue: Self.time(from: current))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Choose Reminder")
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

            ForEach(ReminderPreference.NamedChoice.allCases) { choice in
                row(
                    title: choice.title,
                    detail: choice.detail,
                    systemImage: choice.systemImage,
                    isSelected: current.selects(choice)
                ) {
                    onSelect(choice.preference)
                    dismiss()
                }
            }

            row(
                title: "Custom",
                detail: current.customDetail,
                systemImage: "clock.badge.questionmark",
                isSelected: current.isCustomChoice
            ) {
                isEditingCustom = true
            }

            if isEditingCustom {
                customEditor
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)
        }
        .frame(width: 380, height: 400)
    }

    /// The inline custom-time editor, revealed by the Custom row.
    private var customEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            DatePicker(
                "Reminder time",
                selection: $customTime,
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()

            Button("Set Reminder") {
                onSelect(.custom(Self.storageValue(for: customTime)))
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    /// One radio row, matching the source's `radioRow`.
    private func row(
        title: String,
        detail: String?,
        systemImage: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(isSelected ? .primary : .secondary)
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Time conversion

    /// `HH:mm` — the source's `` `${h}:${m}` `` with both parts zero-padded.
    static func storageValue(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", components.hour ?? 9, components.minute ?? 0)
    }

    /// Seeds the picker from a stored custom value, falling back to *now* — which
    /// is what the source's `value={new Date()}` does every time the sheet opens.
    static func time(from preference: ReminderPreference, calendar: Calendar = .current) -> Date {
        guard case .custom(let raw) = preference, let clock = clockParts(raw) else {
            return Date()
        }
        return calendar.date(
            bySettingHour: clock.hour,
            minute: clock.minute,
            second: 0,
            of: Date()
        ) ?? Date()
    }

    private static func clockParts(_ raw: String) -> (hour: Int, minute: Int)? {
        let parts = raw.split(separator: ":")
        guard let first = parts.first, let hour = Int(first) else { return nil }
        let minute = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        return (hour, minute)
    }
}
