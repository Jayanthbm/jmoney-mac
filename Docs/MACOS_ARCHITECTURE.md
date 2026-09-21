# Jmoney macOS — Architecture

> Populated after analyzing the React Native application's architecture and business behavior.
> Last updated: 2026-09-21 (Phase 9 goals implemented on top of the shell, data layer, dashboard, transactions and budgets).

## Status

Analysis complete (Phase 1, re-verified — see DATA_ARCHITECTURE.md §8). **App shell implemented
(Phase 4)**. **Data layer implemented (Phase 5)**: GRDB WAL pool, v1 migration mirroring the RN
schema, column-faithful DTOs, and the timestamp-rules port. **Dashboard implemented (Phase 6)**:
metrics, daily-limit/pay-day calculations, the seven widget cards, the Today's Activity drill-down,
and the native progress views. **Transactions implemented (Phase 7)**: the sectioned list, the
filter/search/statistics layer, the editor, soft deletion, and the shared transaction row.
**Budgets implemented (Phase 8)**: month spending over the transaction ledger, the pace-bar list,
month navigation with the same data-range bounds as the source, sorting, the editor, soft deletion,
and the per-budget drill-down. **Goals implemented (Phase 9)**: the progress list, the three sort
orders, the editor with its live preview, soft deletion, and the shared first-open sync predicate —
all unit tested (200 tests green).
Next: Phase 10 (Reports).

---

## 1. Source App Summary (functional reference)

The React Native app is an offline-first personal finance tracker:

- **Expo Router** file-based navigation: 5 bottom tabs (Dashboard, Transactions, Budgets, Reports,
  Settings) + modal sheets (add transaction, add quick transaction) + stack screens (goals, calendar,
  categories, payees, groups, quick transactions, daily-limit detail, 11 report screens).
- **Local SQLite** (`jmoney.db`, WAL) is the single source of truth for the UI; Supabase is the sync
  target and auth provider. All screens read/write local DB synchronously-fast and trigger background
  sync.
- **State**: React contexts for auth/theme/toast; screen-level hooks own data loading; cross-screen
  refresh via `DeviceEventEmitter` events (`module_refreshed`).
- **Business logic** lives in `src/services/*` and `src/db/*Queries*` (SQL aggregations), with pure
  calculation helpers (daily limit, pay day, goal/budget sorting, report comparison) that are unit
  tested. The macOS port must reproduce these calculations exactly.
- **Sync-specific push details verified in source**: budget interval normalized `Monthly`→`Month`
  and empty-category budgets skipped on push; `is_living_cost` never leaves the device; timestamps
  are saved as UTC ISO and converted to local wall-clock at push. Full detail in
  DATA_ARCHITECTURE.md §2–§4.

## 2. macOS Technology Decisions

| Concern | Decision | Rationale |
| --- | --- | --- |
| UI framework | SwiftUI, app-scene lifecycle | Modern native Mac experience; XcodeGen project already configured |
| Minimum target | macOS 14 Sonoma | `@Observable` macro, modern `NavigationSplitView`; revisit if user requires older |
| Persistence | SQLite via **GRDB.swift** (SPM), schema mirroring the RN schema | See DATA_ARCHITECTURE.md — preserves proven SQL aggregations and sync protocol |
| Cloud | **supabase-swift** (SPM), Keychain session storage | Same auth + Postgres backend as RN app |
| App structure | MVVM with `@Observable` view models; no business logic in views | Master prompt §13 requires testable business logic |
| Concurrency | Swift Concurrency; sync engine on background executor; UI reads via async GRDB observers | RN app blocks UI thread rarely; macOS must keep main thread free |
| Reactive data | GRDB `ValueObservation` replaces `DeviceEventEmitter` module refresh events | Screens update automatically when underlying tables change |
| Security | LocalAuthentication (Touch ID) + Keychain | Replaces expo-local-authentication + AsyncStorage session |
| Notifications | UserNotifications framework | Daily reminders |
| Location | CoreLocation | Optional transaction GPS tagging |
| Connectivity | NWPathMonitor | Replaces NetInfo |

## 3. Target Module Layout

```
Jmoney/
├── App/
│   ├── JmoneyApp.swift            # @main: WindowGroup + Settings scene + Commands  [Phase 4 ✓]
│   ├── AppCommands.swift          # ⌘N/⌘⇧N new+quick transaction, ⌘F find, Data menu ⌘R  [Phase 4 ✓]
│   └── AppState.swift             # @Observable shell state: selection, sheets, search,
│                                  #   status bar (AppEnvironment-style service wiring lands in Phase 5)
├── Navigation/
│   ├── AppSection.swift           # Sidebar destinations enum  [Phase 4 ✓]
│   ├── SidebarView.swift          # NavigationSplitView sidebar  [Phase 4 ✓]
│   ├── RootView.swift             # Auth gate + split view + sheets + detail routing  [Phase 4 ✓]
│   └── StatusBarView.swift        # Bottom status bar (sync status, messages)  [Phase 4 ✓]
├── Features/
│   ├── Auth/                      # AuthGateView placeholder (mock session)  [Phase 4 ✓; real auth Phase 14]
│   ├── Dashboard/                 # DashboardViewModel (@Observable) + widgets: daily limit,
│   │                              #   remaining, pay day, top categories, month/year summaries,
│   │                              #   net worth, Today's Activity sheet, shared card container  [Phase 6 ✓]
│   ├── Transactions/              # TransactionsViewModel + editor view model, sectioned list,
│   │                              #   filter popovers (date/multi-select/stats), shared row,
│   │                              #   editor sheet, editor-target enum  [Phase 7 ✓]
│   ├── Budgets/                   # BudgetsViewModel + editor view model, list with pace bar,
│   │                              #   month stepper + period popover + sort menu, editor sheet,
│   │                              #   drill-down sheet, editor-target enum  [Phase 8 ✓]
│   ├── Goals/                     # GoalsViewModel + editor view model, progress list, sort menu,
│   │                              #   editor sheet, editor-target enum  [Phase 9 ✓]
│   ├── Reports/                   # ReportDestination enum [Phase 6 ✓]; index + 11 report pages
│   │                              #   + drill-down [Phase 10]
│   ├── Calendar/                  # [Phase 11]
│   ├── Categories/  Payees/  Groups/  QuickTransactions/   # [Phase 12]
│   └── Settings/                  # Pane + ⌘, scene views   [Phase 13]
├── Services/
│   ├── DatabaseService.swift      # GRDB WAL pool + v1 migration (exact RN schema)  [Phase 5 ✓]
│   ├── SyncService.swift          # Full sync coordinator (mirror of syncService.ts)   [Phase 14]
│   ├── Sync/                      # Per-entity push/pull (transactions, budgets, goals,
│   │                              #   categories, payees, quick transactions, groups)   [Phase 14]
│   ├── SupabaseService.swift      # Client config, session persistence   [Phase 14]
│   ├── DashboardService.swift     # Metrics + daily-limit + payday + date-window calculations
│   │                              #   (pure, testable) and the dashboard queries   [Phase 6 ✓]
│   ├── TransactionService.swift   # Fetch/filter/sections/stats/lookups + save & soft delete
│   │                              #   (mirror of transactionService.ts + transactionQueries.ts)  [Phase 7 ✓]
│   ├── BudgetService.swift        # Month spending, sorting, month-range bounds, category JSON
│   │                              #   (mirror of budgetService.ts + budgetQueries.ts)  [Phase 8 ✓]
│   ├── GoalService.swift          # Progress maths, sorting, fetch + save & soft delete
│   │                              #   (mirror of goalService.ts + metaQueries.ts)  [Phase 9 ✓]
│   ├── ReportService.swift  CalendarService.swift
│   ├── CategoryService.swift  PayeeService.swift  GroupService.swift  QuickTransactionService.swift
│   ├── NotificationService.swift  # Daily reminders   [Phase 13]
│   └── LocationService.swift      # GPS tagging   [Phase 7]
├── Models/                        # 7 DTOs, column names identical to the RN schema  [Phase 5 ✓]
├── Stores/
│   └── SessionStore.swift         # @Observable session (mock now; Supabase+Keychain Phase 14)  [Phase 4 ✓]
├── Support/
│   ├── Formatters.swift           # ₹/en-IN currency, English date patterns, transaction timestamp
│   │                              #   display, budget period labels  [Phase 6 ✓, Phase 7 ✓, Phase 8 ✓]
│   ├── ProgressViews.swift        # Native progress ring + bar (replaces the RN circular-progress trick)  [Phase 6 ✓]
│   ├── Timestamps.swift           # transactionTimestamp.ts port + `instant`/`utcISOString`  [Phase 5 ✓, Phase 7 ✓]
│   ├── Validators.swift           # validators.ts port (amount + transaction + budget + goal)  [Phase 7–9 ✓]
│   └── InitialSyncGuard.swift     # Shared first-open sync predicate (goals + budgets)  [Phase 9 ✓]
JmoneyTests/                       # 200 tests: schema/defaults/indexes, record round-trips, timestamp rules,
                                   #   dashboard calculations/queries, formatters, widget render smoke,
                                   #   transaction filters/sections/validation, transaction SQL & writes,
                                   #   budget card maths/sorting/month bounds/validation, budget SQL,
                                   #   drill-down & writes, budget render smoke, goal card maths/sorting/
                                   #   validation, goal SQL & writes, goal render smoke  [Phase 5–9 ✓]
```

## 4. macOS Interaction Mapping

| Mobile pattern | macOS equivalent |
| --- | --- |
| Bottom tabs | Sidebar (`NavigationSplitView`) |
| Modal bottom sheet (add transaction) | Sheet (⌘N) |
| FAB add buttons | Toolbar `+` and File > New commands |
| Filter bottom sheets | Popovers from filter toolbar buttons |
| FlashList with sticky headers | `List`/`Table` with section headers; lazy paging for large datasets |
| Long-press card actions | Context menus (edit, delete, filter by payee/category) |
| Confirmation bottom sheets | Native confirmation dialogs |
| Pull-to-refresh / refresh icons | ⌘R + toolbar refresh button |
| Header "Synced Xm ago" subtitle | Toolbar subtitle / status area |
| Toasts | Transient status feedback (toolbar/sheet banners); errors as alerts |
| Reorder arrows | Drag-and-drop reordering |
| Biometric lock overlay | Secure field + LAContext on window activation |
| Report grid/list toggle | Toolbar view style toggle |
| Vertical scroll of dashboard cards | Two-column adaptive `Grid` (net worth spans both columns) |
| Quarter-segment border "circular progress" | Real stroked progress ring (`Circle().trim`) |
| Collapsible search + filter panel | `.searchable` toolbar field plus toolbar filter buttons |
| Filter bottom sheets | Popovers anchored to the toolbar buttons |
| Icon-tile multi-select grid | Checkbox list with a search field |
| Swipe-to-edit / swipe-to-delete | Context menu, `⌫` on the selection, double-click to edit |
| FlashList pinned (sticky) date headers | Native `List` sections with per-day headers and totals |
| Long-press card actions | Context menu (edit, delete, filter by payee/category) |

Keyboard: ⌘N new transaction, ⌘⇧N quick transaction, ⌘F search, ⌘R sync, ⌘, settings,
Delete remove selection, Return open selection, Escape dismiss sheets — no conflicts with
standard macOS shortcuts.

## 5. Data Flow

```
View (@Observable VM) ⇄ GRDB ValueObservation ⇄ SQLite (WAL)
                                   ⇅ (background)
                                SyncService ⇄ Supabase (auth + REST)
```

- **Reads**: views observe database tables; no manual refresh events.
- **Writes**: view model → service → local DB (marks `sync_status = 1`) → background push trigger.
- **Sync**: same push/pull protocol as RN (see DATA_ARCHITECTURE.md); re-entrancy guarded; per-entity
  last-sync timestamps in `UserDefaults`.
- **Session**: Supabase session in Keychain; auth gate at app scene; sign-out keeps local data.

## 6. Error Handling & Edge Behavior (preserve from RN)

- Session init timeout (7 s) so the app never hangs on the auth gate.
- Sync failures leave `sync_status = 1` for retry; user-visible error states on dashboard sync modal.
- Location fetch: last-known fallback → progressive accuracy → graceful disable.
- Validation errors surfaced as inline/toast messages (amount, category required, etc.).
- Empty states on every list; loading states on every async surface.

## 7. Performance Considerations

- Thousands of transactions: use SQL-side filtering/aggregation (as RN does), lazy list loading,
  indexed queries (same indexes as RN schema), avoid loading full tables into memory.
- Aggregate queries (reports, dashboard) run on a background read-only DB connection.
- Sync chunking (1000 rows) preserved for large transaction pulls.

## 8. Open Items

- None blocking Phase 6. Data-layer decisions are recorded in DATA_ARCHITECTURE.md.
- Shell notes: ⌘F is owned by Edit > Find… (no TextEditingCommands are included, so there is no
  conflict); Find currently presents the search field on the Transactions view only. ⌘R lives in a
  custom Data menu and reports "not connected" until the sync engine exists. The auth gate uses a
  mock session; sign-out is added with real auth (Phase 14).
- Data-layer notes: `DatabaseService` is `@Observable` and injected via `.environment`; the pool
  opens + migrates in `prepare()` (idempotent) called from `RootView.task`, mirroring the RN boot
  order (`initDB()` before navigation). Status bar reports "Local database ready."/failure. Tests
  run via the explicit `Jmoney` scheme (`xcodebuild … test -destination 'platform=macOS'`).
- Dashboard notes: `Services/DashboardService.swift` is the reference service shape — pure static
  calculations plus parameterized GRDB queries that take a `Database`, so every rule is testable
  against an in-memory `DatabaseQueue` with no app running. The seven metric queries share one
  `pool.read` (one consistent snapshot) instead of the RN app's seven parallel queries. Report
  click-through is recorded on `AppState.requestedReport` and echo-rendered by the Reports
  placeholder until Phase 10. `TodaysActivityView` now uses the shared `TransactionRow`. ⌘R still
  reports "not connected" (Phase 14).
- Transactions notes: `AppState.transactionEditor` drives the editor sheet (⌘N sets `.new`, a row
  sets `.edit(tx)`); `AppState.dataRevision` / `markDataChanged()` replaces the RN
  `DeviceEventEmitter 'module_refreshed'` events — Dashboard and Transactions both reload on it.
  Writes go through `TransactionService.save` (GRDB upsert, `sync_status = 1`) and
  `softDelete`; the editor never drops saved coordinates. Outstanding Phase 7 items: location
  tagging, quick-transaction presets, and the Material→SF Symbol category icon mapping (Phase 12).
  `TransactionRow`, `TransactionDayHeader`, `ProgressViews` and `Validators` are the pieces later
  phases should reuse rather than rebuild.
- Budgets notes: `Services/BudgetService.swift` follows the dashboard/transaction service shape
  (pure statics + parameterized queries over a `Database`). `BudgetsViewModel` reads the earliest
  transaction date and the expense categories in one snapshot with the list. Month and sort changes
  are *observed* (`onChange` on `selectedMonth` / `sortKey` / `ascending`) rather than driven
  imperatively, so the stepper, the period popover, "Back to Today" and the sort menu all reload
  through the same path. `selectedMonth` is normalized to the first of the month, which also removes
  the JS `setMonth` overflow quirk (Jan 31 → "February" rolls to Mar 3 in RN). The drill-down reuses
  `TransactionRow`. The first-open sync guard is already ported as a pure predicate
  (`BudgetsViewModel.shouldRunInitialSync`) for Phase 14 to call; there is no sync engine yet, so the
  RN header's manual sync button is not reproduced.
- Goals notes: `Services/GoalService.swift` is deliberately the smallest service — a list query, a
  pure `cardInfo`, a stable three-key comparator, and the write pair. Two source quirks are preserved
  and tested rather than smoothed over: an empty "Currently Saved" is an error (JS `parseFloat('')` is
  `NaN`, reported as "Current amount cannot be negative"), and the header caption capitalizes the raw
  sort value ("Amount") while the sort sheet labels the same mode "Target Amount". The first-open
  sync condition now lives in `Support/InitialSyncGuard.swift` and is shared with budgets, each with
  its own thin named wrapper.
- Reports (Phase 10) is read-only and the largest remaining surface: 11 report types over the same
  four tables, with period comparisons and drill-downs. Follow the service pattern but skip the write
  path, and consume `AppState.requestedReport` for the dashboard click-through.
