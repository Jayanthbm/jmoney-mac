import SwiftUI

/// The month grid — `CalendarGrid.tsx`.
///
/// Seven equal columns starting on Sunday with blanks for the days before the
/// 1st, day numbers only (the source's grid carries **no** per-day amounts; the
/// selected day's total lives in the day summary), and the selected day filled
/// with the accent colour.
///
/// One macOS addition: when the selected day is not today, today gets a thin
/// accent outline. On the source the two coincide at launch, so the distinction
/// only appears after you navigate away, where a desktop pointer benefits from
/// knowing where "today" is.
struct CalendarMonthGrid: View {
    let viewModel: CalendarViewModel

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(viewModel.weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
            }

            ForEach(0..<viewModel.leadingSlots, id: \.self) { _ in
                Color.clear
                    .frame(height: 36)
                    .accessibilityHidden(true)
            }

            ForEach(viewModel.days, id: \.self) { day in
                dayCell(day)
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let isSelected = viewModel.isSelected(day)
        let isToday = viewModel.isToday(day)
        let number = viewModel.calendar.component(.day, from: day)

        return Button {
            viewModel.select(day)
        } label: {
            Text("\(number)")
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 10).fill(Color.accentColor)
                    } else if isToday {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.accentColor, lineWidth: 1.5)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: day, number: number, isToday: isToday))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func accessibilityLabel(for day: Date, number: Int, isToday: Bool) -> String {
        var label = AppFormat.format(day, "MMMM d, yyyy", calendar: viewModel.calendar)
        if isToday { label += ", today" }
        return label
    }
}
