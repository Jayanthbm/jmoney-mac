import SwiftUI

/// The period picker behind the period label — `YearMonthSelector` as used by the
/// report screens.
///
/// Like the budgets phase's picker: a popover with a year menu and a month grid,
/// the same disabled states as the source, and an immediate apply (the RN sheet's
/// "Confirm Selection" only closes it). Yearly reports show only the year menu,
/// matching `showMonths={false}`.
struct ReportPeriodPicker: View {
    let viewModel: ReportDetailViewModel
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

            if viewModel.destination.showsMonth {
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
        let selectable = isSelectable(monthIndex: index)
        let selected = index == viewModel.monthIndex

        Button {
            viewModel.select(year: viewModel.year, monthIndex: index)
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

    /// Newest year first, down to the year of the earliest transaction.
    private var selectableYears: [Int] {
        let maximum = viewModel.calendar.component(.year, from: viewModel.now)
        let minimum = viewModel.calendar.component(.year, from: viewModel.minDate)
        guard minimum <= maximum else { return [maximum] }
        return Array((minimum...maximum).reversed())
    }

    /// The source disables a month outside `[startOfMonth(minDate),
    /// endOfMonth(maxDate)]`; the stepper enforces the same bounds.
    private func isSelectable(monthIndex: Int) -> Bool {
        let calendar = viewModel.calendar
        guard let target = calendar.date(
            from: DateComponents(year: viewModel.year, month: monthIndex + 1, day: 1)
        ) else { return false }

        let minimum = calendar.date(
            from: calendar.dateComponents([.year, .month], from: viewModel.minDate)
        ) ?? viewModel.minDate
        let maximum = calendar.date(
            from: calendar.dateComponents([.year, .month], from: viewModel.now)
        ) ?? viewModel.now

        // Yearly reports only care about the year.
        if !viewModel.destination.showsMonth {
            return calendar.component(.year, from: target) <= calendar.component(.year, from: maximum)
                && calendar.component(.year, from: target) >= calendar.component(.year, from: minimum)
        }
        return target >= minimum && target <= maximum
    }

    /// Picking a year keeps the month number, exactly as the source's
    /// `newDate.setFullYear(y)` does — landing outside the data range is allowed
    /// and simply shows which months are unreachable.
    private var yearBinding: Binding<Int> {
        Binding(
            get: { viewModel.year },
            set: { viewModel.select(year: $0, monthIndex: viewModel.monthIndex) }
        )
    }
}
