import SwiftUI

/// The month/year picker behind a period label — the RN `YearMonthSelector` as
/// the budgets, reports and calendar screens use it.
///
/// Value-driven rather than view-model-driven, because three screens now share
/// it: the caller supplies the years to offer, which months are reachable, and
/// what a selection means (budgets and reports replace the whole period, the
/// calendar also moves the selected day).
///
/// Like the source: the year is a menu, the months a 3-column grid, out-of-range
/// entries are disabled, and a pick applies immediately (the RN sheet's
/// "Confirm Selection" button only closes the sheet). `showsMonth: false` renders
/// the year menu alone, matching `showMonths={false}` on the yearly reports.
struct MonthYearPicker: View {
    let year: Int
    let monthIndex: Int
    var showsMonth = true
    /// Newest first, down to the earliest period with data.
    let selectableYears: [Int]
    let isMonthSelectable: (Int) -> Bool
    let onSelect: (_ year: Int, _ monthIndex: Int) -> Void

    @Environment(\.dismiss) private var dismiss

    private static let monthNames = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    ]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SELECT PERIOD")
                .font(.caption2.weight(.heavy))
                .tracking(1)
                .foregroundStyle(.secondary)

            Picker("Year", selection: yearBinding) {
                ForEach(selectableYears, id: \.self) { year in
                    Text(String(year)).tag(year)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsMonth {
                Divider()
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(Array(Self.monthNames.enumerated()), id: \.offset) { index, name in
                        monthButton(index: index, fullName: name)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 260)
    }

    @ViewBuilder
    private func monthButton(index: Int, fullName: String) -> some View {
        let selectable = isMonthSelectable(index)
        let selected = index == monthIndex

        Button {
            onSelect(year, index)
            dismiss()
        } label: {
            Text(String(fullName.prefix(3)))
                .font(.caption.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .foregroundStyle(
            selectable ? (selected ? Color.accentColor : Color.primary) : Color.secondary.opacity(0.4)
        )
        .background(
            selected ? Color.accentColor.opacity(0.15) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .disabled(!selectable)
        .accessibilityLabel(fullName)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    /// Picking a year keeps the month number — `newDate.setFullYear(y)` in the
    /// source. It can land on a month outside the data range; the grid shows which
    /// ones those are, and the source does not clamp either.
    private var yearBinding: Binding<Int> {
        Binding(
            get: { year },
            set: { onSelect($0, monthIndex) }
        )
    }
}
