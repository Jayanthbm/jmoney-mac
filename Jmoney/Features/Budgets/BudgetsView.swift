import GRDB
import SwiftUI

/// Budgets — the native equivalent of the RN budgets tab.
///
/// The mobile layout maps onto Mac as: a toolbar month stepper whose picker becomes
/// a popover, a toolbar sort menu (the RN sort sheet), row actions in a context menu
/// (the RN long-press), a drill-down sheet on double-click (the RN card tap), and a
/// toolbar `+` for the editor (the RN floating action button).
///
/// Month and sort changes are observed rather than driven imperatively, so the
/// stepper, the period picker, "Back to Today", and the sort menu all reload
/// through the same path. The period popover is the shared `MonthYearPicker`,
/// which the reports and calendar screens use too.
///
/// Phase 14 wires the RN header's manual sync button (the toolbar's sync item)
/// and the first-open auto-sync guard, whose pure predicate now gets called.
struct BudgetsView: View {
    @Environment(AppState.self) private var appState
    @Environment(SessionStore.self) private var sessionStore
    @Environment(DatabaseService.self) private var database

    private var viewModel: BudgetsViewModel {
        appState.budgetsViewModel
    }
    @State private var selection: BudgetService.EnrichedBudget.ID?
    @State private var editorTarget: BudgetEditorTarget?
    @State private var drillDownBudget: BudgetService.EnrichedBudget?
    @State private var pendingDeletion: BudgetService.EnrichedBudget?
    @State private var showMonthPicker = false

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.budgets.isEmpty {
                ProgressView("Loading budgets…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let message = viewModel.errorMessage, viewModel.budgets.isEmpty {
                errorState(message)
            } else if viewModel.budgets.isEmpty {
                emptyState
            } else {
                listContent
            }
        }
        .navigationTitle("Budgets")
        .toolbar { toolbarContent }
        .onChange(of: viewModel.selectedMonth) { _, _ in Task { await reload() } }
        .onChange(of: viewModel.sortKey) { _, _ in Task { await reload() } }
        .onChange(of: viewModel.ascending) { _, _ in Task { await reload() } }
        .onChange(of: appState.dataRevision) { _, _ in
            Task {
                await viewModel.loadLookups(pool: database.pool, userId: sessionStore.userId)
                await reload()
            }
        }
        // Phase 16: File > New Budget switches here and raises the request.
        .onChange(of: appState.sectionEditorRequestID) { _, _ in
            guard appState.selectedSection == .budgets else { return }
            editorTarget = .new
        }
        .onChange(of: appState.sectionSyncRequestID) { _, _ in
            guard appState.selectedSection == .budgets else { return }
            appState.requestEntitySync(.budgets)
        }
        .task {
            await viewModel.loadLookups(pool: database.pool, userId: sessionStore.userId)
            await reload()
            await runInitialSyncIfNeeded()
        }
        .sheet(item: $editorTarget) { target in
            BudgetEditorView(target: target) { budget in
                // The RN sheet asks its parent to confirm, and the parent closes the
                // sheet as part of the delete.
                pendingDeletion = viewModel.budgets.first { $0.id == budget.id }
                    ?? BudgetService.EnrichedBudget(budget: budget, spent: 0)
                editorTarget = nil
            }
        }
        .sheet(item: $drillDownBudget) { budget in
            BudgetDrillDownView(
                pool: database.pool,
                userId: sessionStore.userId,
                budget: budget,
                monthRange: viewModel.monthRange,
                subtitle: viewModel.monthFullLabel
            )
        }
        .alert(
            "Delete Budget?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { budget in
            Button("Confirm Delete", role: .destructive) { delete(budget) }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: { budget in
            Text("This action cannot be undone. Are you sure you want to delete the budget \"\(budget.name)\" from your records?")
        }
    }

    // MARK: - List

    private var listContent: some View {
        VStack(spacing: 0) {
            toolsBar

            GeometryReader { geometry in
                ScrollView {
                    let columns = geometry.size.width >= 700
                        ? [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
                        : [GridItem(.flexible())]

                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(viewModel.budgets) { budget in
                            BudgetRow(
                                budget: budget,
                                info: viewModel.cardInfo(for: budget),
                                startLabel: viewModel.monthRange.startLabel(calendar: viewModel.calendar),
                                endLabel: viewModel.monthRange.endLabel(calendar: viewModel.calendar),
                                isCurrentMonth: viewModel.isCurrentMonth,
                                daysInMonth: viewModel.daysInMonth,
                                todayProgress: viewModel.todayProgress
                            )
                            .onTapGesture(count: 2) { drillDownBudget = budget }
                            .contextMenu { rowMenu(for: budget) }
                        }
                    }
                    .padding(16)
                }
            }
            .onDeleteCommand { requestDeletion(for: selection) }
        }
    }

    /// The sort caption and "Back to Today", which the RN screen keeps in a row
    /// above the list (the button only appears once you leave the current month).
    private var toolsBar: some View {
        HStack(spacing: 12) {
            Text(viewModel.sortCaption)
                .font(.caption.weight(.bold))
                .tracking(0.5)
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            if !viewModel.isCurrentMonth {
                Button("Back to Today") {
                    viewModel.goToCurrentMonth()
                }
                .buttonStyle(.borderless)
                .font(.caption.weight(.bold))
                .help("Return to the current month")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    @ViewBuilder
    private func rowMenu(for budget: BudgetService.EnrichedBudget) -> some View {
        Button("View Transactions") { drillDownBudget = budget }

        Button("Edit…") { editorTarget = .edit(budget.budget) }

        Divider()

        Button("Delete…", role: .destructive) { pendingDeletion = budget }
    }

    private func requestDeletion(for id: BudgetService.EnrichedBudget.ID?) {
        guard let id, let budget = viewModel.budgets.first(where: { $0.id == id }) else { return }
        pendingDeletion = budget
    }

    private func delete(_ budget: BudgetService.EnrichedBudget) {
        Task {
            let deleted = await viewModel.delete(
                budget, pool: database.pool, userId: sessionStore.userId
            )
            pendingDeletion = nil
            guard deleted else { return }
            if selection == budget.id { selection = nil }
            appState.markDataChanged()
            appState.statusMessage = "Budget deleted."
            // The RN delete modal also fires `handleBudgetSync` fire-and-forget.
            appState.requestEntitySync(.budgets)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                viewModel.goToPreviousMonth()
            } label: {
                Label("Previous Month", systemImage: "chevron.left")
            }
            .disabled(!viewModel.canGoToPreviousMonth)
            .help("Previous month")

            Button {
                showMonthPicker = true
            } label: {
                HStack(spacing: 4) {
                    Text(viewModel.monthLabel)
                        .monospacedDigit()
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
            }
            .help("Select a period")
            .popover(isPresented: $showMonthPicker, arrowEdge: .bottom) {
                MonthYearPicker(
                    year: viewModel.selectedMonthYear,
                    monthIndex: viewModel.selectedMonthIndex,
                    selectableYears: viewModel.selectableYears,
                    isMonthSelectable: { monthIndex in
                        viewModel.isMonthSelectable(
                            year: viewModel.selectedMonthYear, monthIndex: monthIndex
                        )
                    },
                    onSelect: { year, monthIndex in
                        viewModel.select(year: year, monthIndex: monthIndex)
                    }
                )
            }

            Button {
                viewModel.goToNextMonth()
            } label: {
                Label("Next Month", systemImage: "chevron.right")
            }
            .disabled(!viewModel.canGoToNextMonth)
            .help("Next month")

            sortMenu
        }

        ToolbarItemGroup(placement: .primaryAction) {
            ManagementSyncButton(
                entity: .budgets,
                action: { appState.requestEntitySync(.budgets) },
                isSyncing: appState.isSyncing
            )

            Button {
                editorTarget = .new
            } label: {
                Label("New Budget", systemImage: "plus")
            }
            .help("New Budget")
        }
    }

    /// The RN sort sheet's behaviour: re-selecting the active mode flips the
    /// direction, picking a different one uses that mode's default.
    private var sortMenu: some View {
        Menu {
            ForEach(BudgetService.SortKey.allCases) { key in
                Button {
                    viewModel.selectSort(key)
                } label: {
                    if key == viewModel.sortKey {
                        Label(
                            "\(key.title) — \(viewModel.ascending ? "Ascending" : "Descending")",
                            systemImage: viewModel.ascending ? "arrow.up" : "arrow.down"
                        )
                    } else {
                        Text(key.title)
                    }
                }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .help("Sort budgets")
    }

    // MARK: - States

    @ViewBuilder
    private func errorState(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't load budgets", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") { Task { await reload() } }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Budgets Found", systemImage: "wallet.bifold")
        } description: {
            Text("Create a budget to track spending across a set of categories each month.")
        } actions: {
            Button("New Budget") { editorTarget = .new }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Actions

    private func reload() async {
        await viewModel.load(pool: database.pool, userId: sessionStore.userId)
    }

    /// The budgets screen's first-open auto-sync: the RN screen's `loadData` runs
    /// `handleBudgetSync` when the list is empty or the last-sync value is not a
    /// timestamp, gated by the `@initial_budget_sync_checked_` flag. The condition
    /// is `BudgetsViewModel.shouldRunInitialSync` (== `InitialSyncGuard`); the flag
    /// write happens in `RootView.finish` after the sync completes.
    private func runInitialSyncIfNeeded() async {
        guard sessionStore.userId != nil, !appState.isSyncing else { return }
        let userId = sessionStore.userId!
        guard
            BudgetsViewModel.shouldRunInitialSync(
                budgetCount: viewModel.budgets.count,
                lastSyncTimestamp: SyncPreference.lastSyncTimestamp(
                    entity: .budgets, userId: userId
                ),
                alreadyChecked: SyncPreference.initialSyncChecked(
                    entity: .budgets, userId: userId
                )
            )
        else { return }
        appState.requestEntitySync(.budgets)
    }
}
