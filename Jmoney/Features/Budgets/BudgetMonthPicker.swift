import SwiftUI

/// The month/year picker behind the period label, mirroring `YearMonthSelector`.
///
/// The RN component is a two-column bottom sheet (years down to the earliest
/// transaction, months with out-of-range entries disabled). Here both columns live
/// in a popover: a year menu and a month grid, with the same disabled states.
///
/// Like the source, a pick applies immediately — the RN `Confirm Selection` button
/// only closes the sheet — so choosing a month dismisses this popover.
struct BudgetMonthPicker: View {
    let viewModel: BudgetsViewModel
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
                ForEach(viewModel.selectableYears, id: \.self) { year in
                    Text(String(year)).tag(year)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(Self.monthNames.enumerated()), id: \.offset) { index, name in
                    monthButton(index: index, fullName: name)
                }
            }
        }
        .padding(16)
        .frame(width: 260)
    }

    @ViewBuilder
    private func monthButton(index: Int, fullName: String) -> some View {
        let year = viewModel.selectedMonthYear
        let selectable = viewModel.isMonthSelectable(year: year, monthIndex: index)
        let selected = viewModel.isSelected(year: year, monthIndex: index)

        Button {
            viewModel.select(year: year, monthIndex: index)
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
    /// source. It can land on a month outside the data range (before the earliest
    /// transaction in that year); the month grid shows which ones those are, and
    /// the source does not clamp either.
    private var yearBinding: Binding<Int> {
        Binding(
            get: { viewModel.selectedMonthYear },
            set: { viewModel.select(year: $0, monthIndex: viewModel.selectedMonthIndex) }
        )
    }
}
