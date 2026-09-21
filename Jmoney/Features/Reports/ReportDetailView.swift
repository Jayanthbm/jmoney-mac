import GRDB
import SwiftUI

/// One report page. The RN app has eleven near-identical screens that differ only
/// in their `ReportSelectors` props, their summary/data switch, and two special
/// cases; here a single page is driven by `ReportDestination`, which carries
/// exactly those flags.
///
/// Special cases, both matching their source screens:
/// * **groups** renders the expandable group›category accordion
///   (`group-summary.tsx`) instead of a flat row list;
/// * **monthlyLivingCosts** adds the living-cost configuration sheet, which
///   writes the local-only `is_living_cost` flag (`living-costs.tsx`).
struct ReportDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(SessionStore.self) private var sessionStore
    @Environment(DatabaseService.self) private var database

    let destination: ReportDestination

    @State private var viewModel: ReportDetailViewModel
    @State private var showPeriodPicker = false
    @State private var showLivingCostConfig = false
    @State private var showDrillDown = false
    @State private var configSearchQuery = ""

    init(destination: ReportDestination) {
        self.destination = destination
        _viewModel = State(initialValue: ReportDetailViewModel(destination: destination))
    }

    var body: some View {
        VStack(spacing: 0) {
            if destination.hasTypeToggle { typeSelector }
            toolsBar
            if destination.isOverview { searchRow }
            Divider()
            content
        }
        .navigationTitle(destination.title)
        .toolbar { toolbarContent }
        .onChange(of: viewModel.type) { _, _ in reload() }
        .onChange(of: viewModel.year) { _, _ in reload() }
        .onChange(of: viewModel.monthIndex) { _, _ in reload() }
        .onChange(of: viewModel.useFullPreviousPeriod) { _, _ in reload() }
        .onChange(of: appState.dataRevision) { _, _ in reload() }
        .task {
            await viewModel.loadBounds(pool: database.pool, userId: sessionStore.userId)
            await reloadNow()
        }
        .sheet(isPresented: $showDrillDown) {
            ReportDrillDownView(
                target: ReportDrillDownTarget(
                    title: viewModel.drillDownTitle,
                    transactions: viewModel.drillDownTransactions
                )
            )
        }
        .sheet(isPresented: $showLivingCostConfig) {
            LivingCostConfigView(
                categories: viewModel.livingCostCategories,
                searchQuery: $configSearchQuery
            ) { category in
                Task {
                    await viewModel.toggleLivingCost(
                        categoryId: category.id,
                        current: category.isLivingCost == 1,
                        searchQuery: configSearchQuery,
                        pool: database.pool,
                        userId: sessionStore.userId
                    )
                }
            }
            .task(id: configSearchQuery) {
                await viewModel.loadLivingCostCategories(
                    searchQuery: configSearchQuery,
                    pool: database.pool,
                    userId: sessionStore.userId
                )
            }
        }
    }

    // MARK: - Selectors

    /// The RN screens' `SegmentedControl` above the period selector. Expense is
    /// the danger colour and Income the success colour in the source.
    private var typeSelector: some View {
        Picker("Type", selection: typeBinding) {
            Text("Expense").tag("Expense")
            Text("Income").tag("Income")
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 320)
        .padding(.top, 12)
        .padding(.horizontal, 16)
        .accessibilityLabel("Transaction type")
    }

    /// The comparison toggle, the "Back to Current …" button, and the sort
    /// caption — the pieces the RN screens keep between the selectors and the
    /// list. The comparison toggle is only offered for the current period, and
    /// only for reports that actually compare (`ReportSelectors` +
    /// `comparisonTypes`).
    private var toolsBar: some View {
        HStack(spacing: 12) {
            if destination.supportsComparison && viewModel.isCurrentPeriod {
                Button {
                    viewModel.setUseFullPreviousPeriod(!viewModel.useFullPreviousPeriod)
                } label: {
                    Label(
                        destination.comparisonToggleTitle,
                        systemImage: viewModel.useFullPreviousPeriod
                            ? "clock.arrow.circlepath" : "clock"
                    )
                    .font(.caption.weight(.bold))
                }
                .buttonStyle(.bordered)
                .tint(viewModel.useFullPreviousPeriod ? .accentColor : nil)
                .help(
                    viewModel.useFullPreviousPeriod
                        ? "Comparing the full previous period"
                        : "Comparing month-to-date against month-to-date"
                )
            }

            if viewModel.showsBackToCurrent {
                Button(destination.backToCurrentTitle) {
                    viewModel.goToCurrentPeriod()
                }
                .buttonStyle(.borderless)
                .font(.caption.weight(.bold))
                .help("Return to the current period")
            }

            Spacer(minLength: 8)

            if viewModel.isLoading {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.bar)
    }

    /// The two overview screens are the only ones with a search field, and the
    /// sort caption sits under it exactly as `category-overview.tsx` lays it out.
    private var searchRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(
                    destination == .payees ? "Search payees…" : "Search categories…",
                    text: searchBinding
                )
                .textFieldStyle(.plain)
                .accessibilityLabel("Search")

                if !viewModel.searchQuery.isEmpty {
                    Button {
                        viewModel.setSearchQuery("")
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(6)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))

            Text(viewModel.sortCaption)
                .font(.caption2.weight(.bold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.data.isEmpty {
            ProgressView("Loading report…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let message = viewModel.errorMessage, viewModel.data.isEmpty {
            ContentUnavailableView {
                Label("Couldn't load this report", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { reload() }
            }
        } else if destination.isSummary {
            if let metrics = viewModel.summaryMetrics, viewModel.presentation.hasData {
                ScrollView { ReportSummaryGrid(metrics: metrics) }
            } else {
                emptyState
            }
        } else {
            reportList
        }
    }

    private var reportList: some View {
        VStack(spacing: 0) {
            if !isSearching || !viewModel.items.isEmpty {
                ReportTotalBanner(
                    total: viewModel.totalAmount,
                    trend: bannerTrend,
                    isIncome: viewModel.bannerIsIncome
                )
                Divider()
            }

            if viewModel.items.isEmpty {
                emptyState
            } else if destination == .groups {
                List(viewModel.items) { item in
                    ReportGroupRow(
                        item: item,
                        type: viewModel.type,
                        loadCategories: {
                            await viewModel.categories(
                                inGroup: item.groupId ?? "",
                                pool: database.pool,
                                userId: sessionStore.userId
                            )
                        },
                        selectCategory: { category in
                            await viewModel.drillDown(
                                fromGroup: item,
                                category: category,
                                pool: database.pool,
                                userId: sessionStore.userId
                            )
                            showDrillDown = true
                        }
                    )
                }
                .listStyle(.inset)
            } else {
                List(viewModel.items) { item in
                    ReportItemRow(
                        item: item,
                        type: viewModel.type,
                        totalAmount: viewModel.totalAmount,
                        showTrends: viewModel.showTrends
                    ) {
                        Task {
                            await viewModel.drillDown(
                                into: item,
                                pool: database.pool,
                                userId: sessionStore.userId
                            )
                            showDrillDown = true
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    /// The banner's trend is only drawn when the report has one (`showTrends`).
    private var bannerTrend: ReportService.Trend? {
        guard viewModel.showTrends else { return nil }
        return ReportService.trend(
            diff: viewModel.totalDiff,
            isIncome: viewModel.bannerIsIncome,
            previousValue: viewModel.previousTotal,
            isSummary: false
        )
    }

    private var isSearching: Bool {
        !viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var emptyState: some View {
        ReportEmptyStateView(
            searchQuery: viewModel.searchQuery,
            destination: destination,
            onClearSearch: { viewModel.setSearchQuery("") },
            onOpenConfig: openLivingCostConfig
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            if destination.showsYear {
                Button {
                    viewModel.step(forward: false)
                } label: {
                    Label("Previous", systemImage: "chevron.left")
                }
                .disabled(!viewModel.canStepBack)
                .help(destination.isYearly ? "Previous year" : "Previous month")

                Button {
                    showPeriodPicker = true
                } label: {
                    HStack(spacing: 4) {
                        Text(viewModel.periodLabel)
                            .monospacedDigit()
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                }
                .help("Select a period")
                .popover(isPresented: $showPeriodPicker, arrowEdge: .bottom) {
                    MonthYearPicker(
                        year: viewModel.year,
                        monthIndex: viewModel.monthIndex,
                        showsMonth: destination.showsMonth,
                        selectableYears: selectableYears,
                        isMonthSelectable: { monthIndex in
                            isMonthSelectable(monthIndex, inYear: viewModel.year)
                        },
                        onSelect: { year, monthIndex in
                            viewModel.select(year: year, monthIndex: monthIndex)
                        }
                    )
                }

                Button {
                    viewModel.step(forward: true)
                } label: {
                    Label("Next", systemImage: "chevron.right")
                }
                .disabled(!viewModel.canStepForward)
                .help(destination.isYearly ? "Next year" : "Next month")
            }

            if destination.isOverview {
                Menu {
                    ForEach(ReportService.SortKey.allCases) { key in
                        Button {
                            viewModel.selectSort(key)
                        } label: {
                            if key == viewModel.sortBy {
                                Label(
                                    "\(key.title) — \(viewModel.sortAscending ? "Ascending" : "Descending")",
                                    systemImage: viewModel.sortAscending ? "arrow.up" : "arrow.down"
                                )
                            } else {
                                Text(key.title)
                            }
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .help("Sort results")
            }

            if destination == .monthlyLivingCosts {
                Button(action: openLivingCostConfig) {
                    Label("Configure Living Costs", systemImage: "gearshape")
                }
                .help("Choose which categories count as living costs")
            }
        }
    }

    // MARK: - Period picker bounds

    /// Newest year first, down to the year of the earliest transaction.
    private var selectableYears: [Int] {
        let maximum = viewModel.calendar.component(.year, from: viewModel.now)
        let minimum = viewModel.calendar.component(.year, from: viewModel.minDate)
        guard minimum <= maximum else { return [maximum] }
        return Array((minimum...maximum).reversed())
    }

    /// The source disables a month outside `[startOfMonth(minDate),
    /// endOfMonth(maxDate)]`; the stepper enforces the same bounds. Yearly
    /// reports only care about the year.
    private func isMonthSelectable(_ monthIndex: Int, inYear year: Int) -> Bool {
        let calendar = viewModel.calendar
        guard
            let target = calendar.date(from: DateComponents(year: year, month: monthIndex + 1, day: 1))
        else { return false }

        let minimum = calendar.date(
            from: calendar.dateComponents([.year, .month], from: viewModel.minDate)
        ) ?? viewModel.minDate
        let maximum = calendar.date(
            from: calendar.dateComponents([.year, .month], from: viewModel.now)
        ) ?? viewModel.now

        if !destination.showsMonth {
            let targetYear = calendar.component(.year, from: target)
            return targetYear >= calendar.component(.year, from: minimum)
                && targetYear <= calendar.component(.year, from: maximum)
        }
        return target >= minimum && target <= maximum
    }

    // MARK: - Bindings

    /// The view model exposes `setType`/`setSearchQuery` rather than writable
    /// properties, because both recompute the presentation (the search) or must
    /// distinguish "same value" from "changed" (the type).
    private var typeBinding: Binding<String> {
        Binding(get: { viewModel.type }, set: { viewModel.setType($0) })
    }

    private var searchBinding: Binding<String> {
        Binding(get: { viewModel.searchQuery }, set: { viewModel.setSearchQuery($0) })
    }

    // MARK: - Actions

    private func openLivingCostConfig() {
        Task {
            await viewModel.loadLivingCostCategories(
                searchQuery: configSearchQuery,
                pool: database.pool,
                userId: sessionStore.userId
            )
            showLivingCostConfig = true
        }
    }

    private func reload() {
        Task { await reloadNow() }
    }

    private func reloadNow() async {
        await viewModel.load(pool: database.pool, userId: sessionStore.userId)
    }
}
