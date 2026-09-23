import GRDB
import SwiftUI

/// Goals — the native equivalent of the RN goals screen.
///
/// The mobile layout maps onto Mac as: a toolbar sort menu (the RN header's sort
/// button + sheet), row actions in a context menu, double-click to edit (the RN
/// card's tap action), and a toolbar `+` for the editor (the RN floating action
/// button). The RN header's "Savings Goals" title becomes the window title and its
/// sort caption moves to the bar above the list.
///
/// Sort changes are observed rather than driven imperatively, so the menu reloads
/// through the same path the other list phases use.
///
/// Phase 14 wires the RN header's manual sync button and the first-open
/// auto-sync guard, whose pure predicate now gets called.
struct GoalsView: View {
    @Environment(AppState.self) private var appState
    @Environment(SessionStore.self) private var sessionStore
    @Environment(DatabaseService.self) private var database

    private var viewModel: GoalsViewModel {
        appState.goalsViewModel
    }
    @State private var selection: Goal.ID?
    @State private var editorTarget: GoalEditorTarget?
    @State private var pendingDeletion: Goal?

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.goals.isEmpty {
                ProgressView("Loading goals…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let message = viewModel.errorMessage, viewModel.goals.isEmpty {
                errorState(message)
            } else if viewModel.goals.isEmpty {
                emptyState
            } else {
                listContent
            }
        }
        .navigationTitle("Goals")
        .toolbar { toolbarContent }
        .onChange(of: viewModel.sortKey) { _, _ in Task { await reload() } }
        .onChange(of: viewModel.ascending) { _, _ in Task { await reload() } }
        .onChange(of: appState.dataRevision) { _, _ in Task { await reload() } }
        // Phase 16: File > New Goal switches here and raises the request; this
        // view presents the editor only when its section is the visible one.
        .onChange(of: appState.sectionEditorRequestID) { _, _ in
            guard appState.selectedSection == .goals else { return }
            editorTarget = .new
        }
        .onChange(of: appState.sectionSyncRequestID) { _, _ in
            guard appState.selectedSection == .goals else { return }
            appState.requestEntitySync(.goals)
        }
        .task {
            await reload()
            await runInitialSyncIfNeeded()
        }
        .sheet(item: $editorTarget) { target in
            GoalEditorView(target: target) { goal in
                // The RN sheet asks its parent to confirm, and the parent closes the
                // sheet as part of the delete.
                pendingDeletion = goal
                editorTarget = nil
            }
        }
        .alert(
            "Delete Goal?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { goal in
            Button("Yes, Delete", role: .destructive) { delete(goal) }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: { _ in
            Text("Are you perfectly sure you want to delete this Goal? This action cannot be undone and will permanently remove it from your dashboard.")
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
                        ForEach(viewModel.goals) { goal in
                            GoalRow(goal: goal, info: viewModel.cardInfo(for: goal))
                                .onTapGesture(count: 2) { editorTarget = .edit(goal) }
                                .contextMenu { rowMenu(for: goal) }
                        }
                    }
                    .padding(16)
                }
            }
            .onDeleteCommand { requestDeletion(for: selection) }
        }
    }

    /// The RN header's sort caption.
    private var toolsBar: some View {
        HStack(spacing: 12) {
            Text(viewModel.sortCaption)
                .font(.caption.weight(.bold))
                .tracking(0.5)
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    @ViewBuilder
    private func rowMenu(for goal: Goal) -> some View {
        Button("Edit…") { editorTarget = .edit(goal) }

        Divider()

        Button("Delete…", role: .destructive) { pendingDeletion = goal }
    }

    private func requestDeletion(for id: Goal.ID?) {
        guard let id, let goal = viewModel.goals.first(where: { $0.id == id }) else { return }
        pendingDeletion = goal
    }

    private func delete(_ goal: Goal) {
        Task {
            let deleted = await viewModel.delete(
                goal, pool: database.pool, userId: sessionStore.userId
            )
            pendingDeletion = nil
            guard deleted else { return }
            if selection == goal.id { selection = nil }
            appState.markDataChanged()
            appState.statusMessage = "Goal deleted."
            // The RN delete modal also fires `handleGoalSync` fire-and-forget.
            appState.requestEntitySync(.goals)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            sortMenu
        }

        ToolbarItemGroup(placement: .primaryAction) {
            ManagementSyncButton(
                entity: .goals,
                action: { appState.requestEntitySync(.goals) },
                isSyncing: appState.isSyncing
            )

            Button {
                editorTarget = .new
            } label: {
                Label("Add New Goal", systemImage: "plus")
            }
            .help("Add New Goal")
        }
    }

    /// The RN sort sheet's behaviour: re-selecting the active mode flips the
    /// direction, picking a different one starts ascending.
    private var sortMenu: some View {
        Menu {
            ForEach(GoalService.SortKey.allCases) { key in
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
        .help("Sort goals")
    }

    // MARK: - States

    @ViewBuilder
    private func errorState(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't load goals", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") { Task { await reload() } }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Goals Found", systemImage: "flag")
        } description: {
            Text("Set a savings goal to track your progress over time.")
        } actions: {
            Button("Add New Goal") { editorTarget = .new }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Actions

    private func reload() async {
        await viewModel.load(pool: database.pool, userId: sessionStore.userId)
    }

    /// The goals screen's first-open auto-sync (the budgets guard's twin): run
    /// `handleGoalSync` when the list is empty or the last-sync value is not a
    /// timestamp, gated by `@initial_goals_sync_checked_`. The flag write happens
    /// in `RootView.finish` after the sync completes.
    private func runInitialSyncIfNeeded() async {
        guard let userId = sessionStore.userId, !appState.isSyncing else { return }
        guard
            GoalsViewModel.shouldRunInitialSync(
                goalCount: viewModel.goals.count,
                lastSyncTimestamp: SyncPreference.lastSyncTimestamp(
                    entity: .goals, userId: userId
                ),
                alreadyChecked: SyncPreference.initialSyncChecked(
                    entity: .goals, userId: userId
                )
            )
        else { return }
        appState.requestEntitySync(.goals)
    }
}
