# Jmoney macOS — Architecture

> Populated after analyzing the React Native application's architecture and business behavior.
> Last updated: 2026-09-22 (Phase 13 settings implemented; analysis re-verified against the source).

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
orders, the editor with its live preview, soft deletion, and the shared first-open sync predicate.
**Reports implemented (Phase 10)**: the 11-report index and a config-driven report page with period
selectors, the previous-period comparison, search/sort, the group accordion, the living-cost
configuration sheet, and drill-downs. **Calendar implemented (Phase 11)**: the bounded month grid,
day selection, the day's net, and the day's transaction list, plus two shared extractions
(`TransactionBounds`, `MonthYearPicker`). **Management entities implemented (Phase 12)**: the four
screens (categories, payees, groups, quick transactions) with their search/sort/reorder/view-mode
controls and editors, the prioritisation writes, the shared Material→SF Symbol icon table, and the
real quick-transaction picker + editor prefill — all unit tested. **Settings implemented (Phase 13)**:
appearance override, daily reminders, Touch ID app lock, manage-data links, the sync row, the
reset-data port with its quirk, and the account/sign-out rows — all unit tested (483 tests green).
**Authentication / Sync implemented (Phase 14)**: real Supabase auth with Keychain-backed sessions
and the 7-second restore guard, the credential-free build-configuration path, the full sync engine
(`SyncService` + the seven entity modules) with its quirks preserved, per-entity and master
last-sync timestamps, the management screens' manual sync buttons + first-open guards +
reorder-exit pushes, the post-save/post-delete syncs, the transaction row's cloud badge, and the
biometric app-lock overlay — 574 tests green. **Import / Export implemented (Phase 15)** — a
deliberate macOS-original addition (the RN app has none): an RFC 4180 CSV codec, transaction/
category/payee/goal CSV exports plus a full seven-table JSON backup, and a name-mapped,
per-row-validated, born-dirty CSV transaction import with a per-row report; File > Export… (⌘E)
and File > Import Transactions… — 599 tests green. **Commands / shortcuts audited and completed
(Phase 16)**: the full menu set (per-section New items with ⇧⌘ bindings, ⇧⌘I import, the Data
menu's section sync) driven by `AppCommands.menuAuditTable` with the HIG conflict rules pinned in
`CommandsTests` — 608 tests green. **Accessibility gaps closed and performance pinned (Phase 17)**:
the two colour-only figures (the day-header net and the filtered net) now state their direction in
words for VoiceOver, and `PerformanceTests` proves the core queries run through indexes
(`EXPLAIN QUERY PLAN`) and that the list/filter/search/dashboard/report/soft-delete paths stay
correct on a 10,000-row ledger — 620 tests green.
Next: Phase 18 (final feature parity audit).

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
│   ├── AppCommands.swift          # The full menu set (New series, Find, Export/Import, Data menu)
│   │                              #   driven by `menuAuditTable`  [Phase 4 ✓, Phase 15 ✓, Phase 16 ✓]
│   └── AppState.swift             # @Observable shell state: selection, sheets, search,
│                                  #   status bar (AppEnvironment-style service wiring lands in Phase 5)
├── Navigation/
│   ├── AppSection.swift           # Sidebar destinations enum  [Phase 4 ✓]
│   ├── SidebarView.swift          # NavigationSplitView sidebar  [Phase 4 ✓]
│   ├── RootView.swift             # Auth gate + split view + sheets + detail routing  [Phase 4 ✓]
│   └── StatusBarView.swift        # Bottom status bar (sync status, messages)  [Phase 4 ✓]
├── Features/
│   ├── Auth/                      # AuthGateView (real sign-in) + AppLockView (the
│   │                              #   biometric lock overlay)  [Phase 4 ✓, Phase 14 ✓]
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
│   ├── Reports/                   # ReportDestination catalog (11 reports) + per-report flags,
│   │                              #   index + NavigationStack, one config-driven report page,
│   │                              #   period picker, summary grid/banner, report rows + group
│   │                              #   accordion, drill-down sheet, living-cost config  [Phase 10 ✓]
│   ├── Calendar/                  # CalendarViewModel, month grid, day summary bar, screen
│   │                              #   (two-pane: grid left, day right)  [Phase 11 ✓]
│   ├── Categories/                # List/grid, tabbed, search/sort, drag reorder, add editor,
│   │                              #   shared icon picker  [Phase 12 ✓]
│   ├── Payees/                    # List/grid, search/sort, drag reorder, add editor  [Phase 12 ✓]
│   ├── Groups/                    # List/grid, search/sort, drag reorder, add/edit editor
│   │                              #   with warning hard delete  [Phase 12 ✓]
│   ├── QuickTransactions/         # Card/list, search, reorder, add/edit editor, and the real
│   │                              #   ⌘⇧N picker that prefills the transaction editor  [Phase 12 ✓]
│   ├── Export/                    # The export sheet (format picker + NSSavePanel) and the import
│   │                              #   sheet (choose → preview → per-row report)  [Phase 15 ✓]
│   └── Settings/                  # Shared settings form (both the sidebar pane and the ⌘,
│                                  #   window host it), view model, reminder-chooser sheet,
│                                  #   settings rows  [Phase 13 ✓]
├── Services/
│   ├── DatabaseService.swift      # GRDB WAL pool + v1 migration (exact RN schema)  [Phase 5 ✓]
│   ├── SyncService.swift          # Full sync coordinator (mirror of syncService.ts)  [Phase 14 ✓]
│   │                              #   + push-only runs and the sync-needed check
│   ├── Sync/                      # Per-entity push/pull (transactions, budgets, goals,
│   │                              #   categories, payees, quick transactions, groups)  [Phase 14 ✓]
│   ├── Auth/                      # AuthProviding + SupabaseAuthService  [Phase 14 ✓]
│   ├── CloudServices.swift        # Config resolution → SupabaseClient + services;
│   │                              #   honest stubs on an unconfigured build  [Phase 14 ✓]
│   ├── ConnectivityMonitor.swift  # NWPathMonitor behind ConnectivityProviding  [Phase 14 ✓]
│   ├── DashboardService.swift     # Metrics + daily-limit + payday + date-window calculations
│   │                              #   (pure, testable) and the dashboard queries   [Phase 6 ✓]
│   ├── TransactionService.swift   # Fetch/filter/sections/stats/lookups + save & soft delete
│   │                              #   (mirror of transactionService.ts + transactionQueries.ts)  [Phase 7 ✓]
│   ├── BudgetService.swift        # Month spending, sorting, month-range bounds, category JSON
│   │                              #   (mirror of budgetService.ts + budgetQueries.ts)  [Phase 8 ✓]
│   ├── GoalService.swift          # Progress maths, sorting, fetch + save & soft delete
│   │                              #   (mirror of goalService.ts + metaQueries.ts)  [Phase 9 ✓]
│   ├── ReportService.swift        # Report queries, previous-period comparison, summary grid,
│   │                              #   stable sorting/search, drill-downs, living-cost flag
│   │                              #   (mirror of reportService.ts + reportQueries.ts)  [Phase 10 ✓]
│   ├── CalendarService.swift      # Month grid build, day net, period day rule + month stepping,
│   │                              #   navigation bounds, day queries
│   │                              #   (mirror of calendarService.ts + the screen's period logic)  [Phase 11 ✓]
│   ├── CategoryService.swift      # List/filter/sort, add-only writes, priority renumber  [Phase 12 ✓]
│   ├── PayeeService.swift         # List/filter/sort, add-only writes, priority renumber  [Phase 12 ✓]
│   ├── GroupService.swift         # List/filter/sort, upsert, hard delete, priorities  [Phase 12 ✓]
│   ├── QuickTransactionService.swift  # Templates: list/filter, upsert, soft delete, priorities,
│   │                              #   identifier rules  [Phase 12 ✓]
│   ├── NotificationService.swift  # Daily reminder scheduling (UserNotifications)  [Phase 13 ✓]
│   ├── BiometricService.swift     # LAContext capability + prompt (the rules are the pure
│   │                              #   `BiometricGate`)  [Phase 13 ✓]
│   ├── SettingsService.swift      # Reset Data (the six-table wipe) + the preference teardown
│   │                              #   (mirror of `resetAppData` + the hook's key list)  [Phase 13 ✓]
│   ├── ExportService.swift        # Transactions (all/filtered) + categories/payees/goals CSV and
│   │                              #   the JSON backup of all seven tables  [Phase 15 ✓]
│   ├── ImportService.swift        # CSV transaction import: name mapping, per-row validation,
│   │                              #   sentinel/id rules, born-dirty inserts, report  [Phase 15 ✓]
│   └── LocationService.swift      # GPS tagging   [Phase 7 — still outstanding]
├── Models/                        # 7 DTOs, column names identical to the RN schema  [Phase 5 ✓]
├── Stores/
│   ├── SessionStore.swift         # @Observable session: supabase-swift + Keychain, restore
│   │                              #   behind the source's 7 s guard  [Phase 4 ✓, Phase 14 ✓]
│   └── AppearanceStore.swift      # @Observable appearance override, shared by both scenes
│                                  #   so ⌘, and the sidebar agree  [Phase 13 ✓]
├── Support/
│   ├── Formatters.swift           # ₹/en-IN currency, English date patterns, transaction timestamp
│   │                              #   display, budget period labels  [Phase 6 ✓, Phase 7 ✓, Phase 8 ✓]
│   ├── ProgressViews.swift        # Native progress ring + bar (replaces the RN circular-progress trick)  [Phase 6 ✓]
│   ├── Timestamps.swift           # transactionTimestamp.ts port + `instant`/`utcISOString`  [Phase 5 ✓, Phase 7 ✓]
│   ├── Validators.swift           # validators.ts port (amount + transaction + budget + goal)  [Phase 7–9 ✓]
│   ├── InitialSyncGuard.swift     # Shared first-open sync predicate (goals + budgets)  [Phase 9 ✓]
│   ├── TransactionBounds.swift    # Shared `MIN(date)` bound (budgets + reports + calendar)  [Phase 11 ✓]
│   ├── MonthYearPicker.swift      # Shared month/year popover (budgets + reports + calendar)  [Phase 11 ✓]
│   ├── CategoryIcon.swift         # The one Material→SF Symbol table + the source's per-context
│   │                              #   fallbacks (transaction/report/config/category)  [Phase 12 ✓]
│   ├── EntityOrdering.swift       # Shared search + name/priority sort + reorder renumbering
│   │                              #   (categories + payees + groups + quick transactions)  [Phase 12 ✓]
│   ├── ViewModePreference.swift   # Per-screen list/grid + card/list preference, keyed exactly
│   │                              #   like the source's AsyncStorage keys  [Phase 12 ✓]
│   ├── AppearancePreference.swift # `app_theme` port (System = the source's absent key)  [Phase 13 ✓]
│   ├── ReminderPreference.swift   # `notification_pref` port: storage, display, the 9:00
│   │                              #   fall-through default  [Phase 13 ✓]
│   ├── BiometricPreference.swift  # `use_biometrics` key + the pure enable/disable gate  [Phase 13 ✓]
│   ├── SyncPreference.swift       # `@last_sync_master_<user>` read/write for the sync row
│   │                              #   and the status bar  [Phase 13 ✓]
│   ├── CSV.swift                  # RFC 4180 encode/decode (BOM, quoting, CRLF+LF)  [Phase 15 ✓]
│   ├── SyncPolicy.swift           # The screens' "should we sync now?" predicates  [Phase 14 ✓]
│   ├── KeychainStore.swift        # Keychain read/write used for the session tokens  [Phase 14 ✓]
│   ├── SupabaseConfig.swift       # Info.plist credential resolution + unconfigured states  [Phase 14 ✓]
│   ├── JSONValue.swift            # Codable-ish JSON for the sync payloads/records  [Phase 14 ✓]
│   └── ManagementSyncButton.swift # The six management screens' shared toolbar sync button
│                                  #   [Phase 14 ✓]
JmoneyTests/                       # 620 tests: schema/defaults/indexes, record round-trips, timestamp rules,
                                   #   dashboard calculations/queries, formatters, widget render smoke,
                                   #   transaction filters/sections/validation, transaction SQL & writes,
                                   #   budget card maths/sorting/month bounds/validation, budget SQL,
                                   #   drill-down & writes, budget render smoke, goal card maths/sorting/
                                   #   validation, goal SQL & writes, goal render smoke, report comparison
                                   #   windows/diffs/summaries/sorting/trends, report SQL & all seven
                                   #   drill-downs, report render smoke, calendar grid/day-net/period
                                   #   rules/bounds, calendar SQL & render smoke, management
                                   #   search/sort/reorder + icon mapping + view-mode preference,
                                   #   category/payee/group/template SQL & write paths,
                                   #   quick-transaction prefill quirks, management render smoke,
                                   #   appearance/reminder/biometric/sync preference rules,
                                   #   reset-data scope + key list + rollback, settings toggle
                                   #   flows, settings render smoke, session/auth flows, the sync
                                   #   engine incl. every preserved quirk, sync foundation rules,
                                   #   push-only runs + lock + guards + button, CSV codec, export
                                   #   rows/backup shape, import mapping/validation/sentinels and
                                   #   the export→import round trip, the menu-audit conflict rules,
                                   #   query-plan index proofs, 10k-row scale correctness
                                   #   [Phase 5–17 ✓]
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
| Biometric lock overlay | Window-covering `AppLockView` on launch + `didBecomeActive`; Touch ID with the OS password fallback |
| Report grid/list toggle | Toolbar view style toggle |
| Vertical scroll of dashboard cards | Two-column adaptive `Grid` (net worth spans both columns) |
| Quarter-segment border "circular progress" | Real stroked progress ring (`Circle().trim`) |
| Collapsible search + filter panel | `.searchable` toolbar field plus toolbar filter buttons |
| Settings tab | Settings *section* in the sidebar **and** a real ⌘, Settings window, both hosting the same form |
| Theme switch (Light/Dark buttons) | Three-way System/Light/Dark segmented picker at the scene root |
| Reminder bottom sheet (radio rows) | Sheet with the same five rows; the custom row expands an inline time field instead of swapping the sheet for a spinner |
| Manage-data rows that `router.push` | Rows that select the matching sidebar section |
| Confirmation bottom sheets (sign out, reset) | Native `.alert` confirmation dialogs |
| In-app toggle (biometrics) | Native `Toggle`; a refused capability test leaves it off and explains why |
| Filter bottom sheets | Popovers anchored to the toolbar buttons |
| Icon-tile multi-select grid | Checkbox list with a search field |
| Swipe-to-edit / swipe-to-delete | Context menu, `⌫` on the selection, double-click to edit |
| FlashList pinned (sticky) date headers | Native `List` sections with per-day headers and totals |
| Long-press card actions | Context menu (edit, delete, filter by payee/category) |
| File exchange (macOS-original, Phase 15) | File > Export… (⌘E) via `NSSavePanel` for the transactions/filtered/categories/payees/goals CSVs and the JSON backup; File > Import Transactions… (⇧⌘I) with an open panel, a preview stage, and a per-row report sheet |
| Section New commands (Phase 16) | File > New Budget/Goal/Category/Payee/Group/Template… (⇧⌘B/G/C/P/T/M): the item selects its sidebar section and raises a request the frontmost section's list view answers |
| Per-section sync (Phase 16) | Data > Sync Transactions and Data > Sync This Section — the menu twins of the screens' toolbar sync buttons |

Keyboard: ⌘N new transaction, ⌘⇧N quick transaction, ⇧⌘B/G/C/P/T/M per-section New, ⌘F search,
⌘R sync, ⌘E export, ⇧⌘I import, ⌘, settings, Delete remove selection, Return open selection,
Escape dismiss sheets — no conflicts with standard macOS shortcuts (audited and pinned by
`CommandsTests`; the three plain-⌘ re-uses each carry a documented safety reason).

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
- Pinned by tests (Phase 17): the core queries are proven to run through indexes via
  `EXPLAIN QUERY PLAN`, and the list/filter/search/dashboard/report/soft-delete paths are verified
  for correctness on a 10,000-row ledger (`PerformanceTests`). Wall-clock assertions are
  deliberately excluded as flaky.

## 8. Open Items

- Phase 14 notes: an unconfigured build (empty `Jmoney.xcconfig`) is a supported state — the auth
  gate explains why sign-in cannot work and sync attempts report the configuration reason rather
  than pretending to succeed. The lock overlay uses `.deviceOwnerAuthentication` (password fallback
  allowed), while the Settings enable flow stays biometrics-only, matching the source's two different
  calls. ⌘R now runs the real full sync.
- Location tagging (create-time GPS capture plus the location edit sheet) remains the one feature
  gap; `Services/LocationService.swift` does not exist yet and the editor shows saved coordinates
  read-only.
- Data-layer decisions are recorded in DATA_ARCHITECTURE.md.
- Settings notes: the sidebar pane and the ⌘, window render one shared `SettingsView`, so the RN
  settings *tab* and the Mac-conventional settings window cannot drift apart; both scenes therefore
  receive the same four environment objects (app state, session, database, appearance).
  `AppearanceStore` sits above both scenes because the override has to reach `.preferredColorScheme`
  at the root — including the Settings scene itself. The capability calls are injected into
  `SettingsViewModel`, which is what makes the biometric and reminder flows unit-testable without
  Touch ID hardware or a notification centre; the *rules* are pure (`BiometricGate`,
  `ReminderPreference`) and the framework wrappers (`BiometricService`, `NotificationService`) are
  thin. `SettingsService.resetLocalData` deliberately does **not** open its own transaction: GRDB
  refuses to nest one inside `DatabasePool.write`, so the caller's write is the transaction the
  source's explicit `BEGIN`/`COMMIT` amounts to. Outstanding from Phase 7: location tagging.
  `Services/LocationService.swift` still does not exist.
- Data-layer notes: `DatabaseService` is `@Observable` and injected via `.environment`; the pool
  opens + migrates in `prepare()` (idempotent) called from `RootView.task`, mirroring the RN boot
  order (`initDB()` before navigation). Status bar reports "Local database ready."/failure. Tests
  run via the explicit `Jmoney` scheme (`xcodebuild … test -destination 'platform=macOS'`).
- Dashboard notes: `Services/DashboardService.swift` is the reference service shape — pure static
  calculations plus parameterized GRDB queries that take a `Database`, so every rule is testable
  against an in-memory `DatabaseQueue` with no app running. The seven metric queries share one
  `pool.read` (one consistent snapshot) instead of the RN app's seven parallel queries. Report
  click-through is recorded on `AppState.requestedReport` and now consumed by `ReportsView`, which
  pushes the requested report. `TodaysActivityView` uses the shared `TransactionRow`. ⌘R still
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
- Reports notes: `Services/ReportService.swift` is the read-only aggregate service — pure statics
  (`previousPeriod`, `applyingComparison`, `summaryMetrics`, `sorted`, `present`, `trend`, the period
  bounds) plus parameterized queries over a `Database`, with `reportData` composing base + previous
  rows. Every report page loads in one `pool.read`. `ReportDestination` is the single source of the
  per-report behaviour flags (which screen shows a type toggle, a month, a comparison, search/sort),
  so one `ReportDetailView` serves all eleven instead of eleven near-identical screens; the two
  genuine special cases (the group accordion in `ReportGroupRow`, the living-cost config sheet) live
  inside it. `ReportPeriodPicker` is the budgets `BudgetMonthPicker` pattern with the report bounds.
  Search/sort exist only on the two overviews, matching the source. `setLivingCost` is the phase's
  only write and is deliberately **not** marked `sync_status = 1` — `is_living_cost` never syncs.
  The comparison windows clamp day overflow instead of rolling it forward as the JS `Date`
  constructor does (Phase 8's `setMonth` decision, applied again). `summaryByGroup`/`yearlyGroup` are
  ported but unreachable from the index, exactly as in the RN app.
- Calendar notes: `Services/CalendarService.swift` holds the grid build, the day net, and the period
  rules so the screen only arranges. Two period rules coexist deliberately because the source uses
  both: an explicit period pick jumps a day that does not fit the new month to the **1st**
  (`getNewDateForPeriod`), while a stepper step *clamps* onto the month end (date-fns `subMonths`).
  The grid is **Sunday-first** (date-fns' default), unlike the Monday-first week the transaction
  quick ranges force. The pane split is calendar-left / day-right; collapse hides the month pane and
  the toolbar keeps "Goto Today" (offered only away from today). Two extractions landed here because
  a third consumer arrived: `Support/TransactionBounds.swift` (the `MIN(date)` bound, shared with
  budgets and reports — reports used to reach into `BudgetService` for it) and
  `Support/MonthYearPicker.swift` (the month/year popover, replacing `BudgetMonthPicker` and
  `ReportPeriodPicker`). `TransactionRow` is again the shared row renderer.
- Management-entity notes: `Support/EntityOrdering.swift` is the shared search + name/priority
  comparator for all four screens (the three `filterAndSort*` services are otherwise identical), with
  JS `Array.prototype.sort` stability restored explicitly and the source's untrimmed-needle search
  quirk preserved — except on quick transactions, whose screen *does* trim. `Support/CategoryIcon.swift`
  is the single Material→SF Symbol table that now backs `TransactionRow`, `ReportItemRow`, the
  living-cost tiles, the category rows and the editor's icon picker; it is a curated table (the
  stored `app_icon` is free text in the source), with the source's `Md`-prefix/kebab normalisation and
  a neutral fallback. `Support/ViewModePreference.swift` stores the per-screen list/grid (and card/list)
  choice in `UserDefaults` under the source's own keys, so the values round-trip across platforms.
  Reordering is drag-and-drop (`onMove`) with the source's up/down arrows kept in the context menu;
  reorder mode still exists because it changes the order, the layout, and where the source pushes.
  `CategoryService` and `PayeeService` are deliberately **add-only** — the source UI offers no
  edit/delete and neither table has a `deleted` column, so a local delete would be resurrected by the
  next full-replace pull. `GroupService.hardDelete` removes the group row and nothing else (member
  transactions keep a dangling `group_id`), while `QuickTransactionService.softDelete` flags the row
  for the push that turns it into a real Supabase delete. `AppState.openTransactions(filters:)` +
  `transactionFilterRequestID` replace the RN route params (`initialSelectedCats` /
  `initialSelectedPayees`) for the category/payee click-through, and
  `AppState.transactionEditor = .template(_)` carries a quick transaction into the editor as a prefill
  (`TransactionService.prefill`), which closes the Phase 7 "quick-transaction presets" item.
