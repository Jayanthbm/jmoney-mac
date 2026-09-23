import GRDB
import SwiftUI

/// Calendar — the native equivalent of the RN `calendar-view` screen, reached
/// from the sidebar and from the dashboard's Pay Day card.
///
/// The mobile layout maps onto Mac as a two-pane split: the month card on the
/// left, and the selected day's summary plus transaction list on the right, so
/// both are visible at once instead of stacked. The source's collapse toggle
/// hides the month pane entirely (the calendar then fills the window), and
/// "Goto Today" moves to the toolbar while keeping the source's rule that it only
/// appears once another day is selected.
///
/// The day's rows use the shared `TransactionRow`, the same renderer as the
/// Transactions list, the dashboard drill-down and the budget/report drill-downs.
struct CalendarView: View {
    @Environment(AppState.self) private var appState
    @Environment(SessionStore.self) private var sessionStore
    @Environment(DatabaseService.self) private var database

    @State private var viewModel = CalendarViewModel()
    @State private var showPeriodPicker = false

    var body: some View {
        HStack(spacing: 0) {
            if !viewModel.isCollapsed {
                monthCard
                Divider()
            }

            VStack(spacing: 0) {
                CalendarDaySummaryBar(
                    heading: viewModel.dayHeading,
                    netText: viewModel.dayNetText,
                    isPositive: viewModel.isDayNetPositive,
                    isCollapsed: viewModel.isCollapsed,
                    showsToggle: viewModel.isCollapsed || !viewModel.dayTransactions.isEmpty,
                    onToggle: { viewModel.toggleCollapsed() }
                )
                Divider()

                dayContent
            }
        }
        .navigationTitle("Calendar")
        .toolbar { toolbarContent }
        .onChange(of: viewModel.selectedDate) { _, _ in reload() }
        .onChange(of: appState.dataRevision) { _, _ in
            Task {
                await viewModel.loadBounds(pool: database.pool, userId: sessionStore.userId)
                await reloadNow()
            }
        }
        .task {
            await viewModel.loadBounds(pool: database.pool, userId: sessionStore.userId)
            await reloadNow()
        }
        .alert(
            "Couldn't load the calendar",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.clearError() } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Month card

    /// The period header and grid, as the RN card's `monthHeader` + `CalendarGrid`
    /// + "Goto Today" stack.
    private var monthCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                Button {
                    viewModel.step(forward: false)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3.weight(.semibold))
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canStepBack)
                .help("Previous month")
                .accessibilityLabel("Previous month")

                Spacer(minLength: 8)

                Button {
                    showPeriodPicker = true
                } label: {
                    HStack(spacing: 4) {
                        Text(viewModel.monthLabel)
                            .font(.headline)
                            .monospacedDigit()
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                }
                .buttonStyle(.plain)
                .help("Select a period")
                .popover(isPresented: $showPeriodPicker, arrowEdge: .bottom) {
                    MonthYearPicker(
                        year: viewModel.selectedMonthYear,
                        monthIndex: viewModel.selectedMonthIndex,
                        selectableYears: viewModel.selectableYears,
                        isMonthSelectable: { monthIndex in
                            viewModel.isMonthSelectable(
                                monthIndex, inYear: viewModel.selectedMonthYear
                            )
                        },
                        onSelect: { year, monthIndex in
                            viewModel.updatePeriod(year: year, monthIndex: monthIndex)
                        }
                    )
                }

                Spacer(minLength: 8)

                Button {
                    viewModel.step(forward: true)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.title3.weight(.semibold))
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canStepForward)
                .help("Next month")
                .accessibilityLabel("Next month")
            }

            CalendarMonthGrid(viewModel: viewModel)
        }
        .padding(16)
        .frame(minWidth: 300, idealWidth: 340, maxWidth: 420)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Month calendar")
    }

    // MARK: - Day

    @ViewBuilder
    private var dayContent: some View {
        if viewModel.isLoading && viewModel.dayTransactions.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.dayTransactions.isEmpty {
            ContentUnavailableView {
                Label("No activity on this day", systemImage: "calendar.badge.exclamationmark")
            } description: {
                Text("Nothing was recorded on \(viewModel.dayHeading).")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            GeometryReader { geometry in
                ScrollView {
                    let columns = geometry.size.width >= 640
                        ? [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
                        : [GridItem(.flexible())]

                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(viewModel.dayTransactions) { transaction in
                            TransactionRow(transaction: transaction)
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            if viewModel.showsGoToToday {
                Button {
                    viewModel.goToToday()
                } label: {
                    Label("Goto Today", systemImage: "calendar.badge.clock")
                }
                .help("Jump back to today")
            }

            Button {
                viewModel.toggleCollapsed()
            } label: {
                Label(
                    viewModel.isCollapsed ? "Show Calendar" : "Hide Calendar",
                    systemImage: viewModel.isCollapsed ? "sidebar.left" : "sidebar.squares.left"
                )
            }
            .help(viewModel.isCollapsed ? "Show the month grid" : "Collapse the month grid")

            Button {
                Task { await reloadNow() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Reload this day's transactions")
        }
    }

    // MARK: - Actions

    private func reload() {
        Task { await reloadNow() }
    }

    private func reloadNow() async {
        await viewModel.load(pool: database.pool, userId: sessionStore.userId)
    }
}
