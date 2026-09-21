import SwiftUI

/// Date-range filter.
///
/// macOS equivalent of `TransactionDateFilterModal.tsx`: optional start/end
/// dates (the RN sheet allows "any date" on either side), the four quick ranges
/// with the week starting Monday, clear, and apply. The source's ordering rule is
/// preserved — moving the start past the end pushes the end, and vice versa.
struct DateRangeFilterPopover: View {
    /// Current bounds when the popover opens; applied back through `onApply`.
    let startDate: String?
    let endDate: String?
    let onApply: (String?, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var tempStart: Date?
    @State private var tempEnd: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select Date Range")
                .font(.headline)

            OptionalDateRow(label: "Start Date", date: $tempStart)
            OptionalDateRow(label: "End Date", date: $tempEnd)

            Text("Quick Ranges")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(TransactionService.DatePreset.allCases) { preset in
                    Button(preset.title) { applyPreset(preset) }
                        .frame(maxWidth: .infinity)
                }
            }

            if tempStart != nil || tempEnd != nil {
                Button("Clear Selected Dates", role: .destructive) {
                    tempStart = nil
                    tempEnd = nil
                }
                .buttonStyle(.borderless)
            }

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Apply Date Filter") {
                    onApply(
                        tempStart.map { AppFormat.yearMonthDay($0) },
                        tempEnd.map { AppFormat.yearMonthDay($0) }
                    )
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 320)
        .onAppear {
            tempStart = startDate.flatMap { AppFormat.date(fromYearMonthDay: $0) }
            tempEnd = endDate.flatMap { AppFormat.date(fromYearMonthDay: $0) }
        }
        .onChange(of: tempStart) { _, newValue in
            if let newValue, let end = tempEnd, newValue > end { tempEnd = newValue }
        }
        .onChange(of: tempEnd) { _, newValue in
            if let newValue, let start = tempStart, newValue < start { tempStart = newValue }
        }
    }

    private func applyPreset(_ preset: TransactionService.DatePreset) {
        let bounds = preset.dates()
        tempStart = bounds.start
        tempEnd = bounds.end
    }
}

/// One side of the date range: a picker once a date is chosen, otherwise a button
/// that starts one. Clearing returns the side to "any date".
private struct OptionalDateRow: View {
    let label: String
    @Binding var date: Date?

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .frame(width: 78, alignment: .leading)

            if date != nil {
                DatePicker(
                    label,
                    selection: Binding(get: { date ?? Date() }, set: { date = $0 }),
                    displayedComponents: .date
                )
                .labelsHidden()

                Button {
                    date = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .help("Clear \(label)")
            } else {
                Button("Any Date") { date = Date() }
            }

            Spacer(minLength: 0)
        }
    }
}

/// Multi-select category/payee/group filter.
///
/// macOS equivalent of `TransactionFilterSelector.tsx`: search, multi-select,
/// apply. The source renders a grid of icon tiles; a checkbox list is the native
/// macOS reading of "pick several from a long list" and scales better with many
/// categories.
struct MultiSelectFilterPopover: View {
    struct Item: Identifiable, Equatable {
        var id: String
        var name: String
    }

    let title: String
    let searchPrompt: String
    let items: [Item]
    let selection: [String]
    let onApply: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var tempSelection: Set<String> = []
    @State private var search = ""

    private var filtered: [Item] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return items }
        return items.filter { $0.name.lowercased().contains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            TextField(searchPrompt, text: $search)
                .textFieldStyle(.roundedBorder)

            if filtered.isEmpty {
                Text(search.isEmpty
                     ? "Nothing to select yet."
                     : "No matching items.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(filtered) { item in
                            Toggle(isOn: binding(for: item.id)) {
                                Text(item.name).lineLimit(1)
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
                }
                .frame(height: 220)
            }

            Divider()

            HStack {
                Button("Clear") { tempSelection.removeAll() }
                Spacer()
                Text("\(tempSelection.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Apply Filters") {
                    onApply(Array(tempSelection))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 300)
        .onAppear { tempSelection = Set(selection) }
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { tempSelection.contains(id) },
            set: { isOn in
                if isOn { tempSelection.insert(id) } else { tempSelection.remove(id) }
            }
        )
    }
}

/// The last-five-months breakdown behind the filtered-total chip.
///
/// Port of `TransactionStatsModal.tsx`: one row per month with the signed net.
struct FilteredStatsPopover: View {
    let statistics: [TransactionService.MonthlyStat]
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Last 5 Months")
                .font(.headline)

            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else if statistics.isEmpty {
                Text("No data for these filters.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                VStack(spacing: 0) {
                    ForEach(statistics) { stat in
                        HStack {
                            Text(stat.month)
                                .font(.body.weight(.semibold))
                            Spacer(minLength: 12)
                            Text("\(stat.net >= 0 ? "+" : "")\(AppFormat.currency(stat.net))")
                                .font(.body.weight(.bold))
                                .foregroundStyle(stat.net >= 0 ? Color.green : Color.red)
                                .monospacedDigit()
                        }
                        .padding(.vertical, 8)
                        .accessibilityElement(children: .combine)

                        if stat.id != statistics.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 260)
    }
}
