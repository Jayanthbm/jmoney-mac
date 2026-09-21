# Jmoney macOS — AI Build Progress

> This file is the persistent handoff/state document for all AI coding agents working on Jmoney macOS.

## Project

**Application:** Jmoney
**Platform:** macOS
**Technology:** Swift + SwiftUI
**Project Path:** `/Users/jayanthbharadwajm/development/jmoney-mac`

## Source Application

The existing React Native application is located at:

`/Users/jayanthbharadwajm/development/jayledger`

The React Native application is the functional source of truth.

The native macOS application is a separate implementation.

### Source Project Rules

* Do not modify `/Users/jayanthbharadwajm/development/jayledger`.
* Use it as the reference implementation.
* Preserve its functionality and business rules.
* The macOS UI should be redesigned specifically for macOS.

---

# Current Status

## Phase 0 — Project Initialization

**Status:** COMPLETE

Completed:

* Native macOS Xcode project created.
* SwiftUI configured.
* XcodeGen configured.
* `Jmoney` target created.
* Bundle identifier configured.
* Automatic Info.plist generation configured.
* Initial SwiftUI application created.
* Initial project successfully builds with `xcodebuild`.

---

## Phase 1 — Analyze React Native Application (+ Phases 2–3 deliverables)

**Status:** COMPLETE

The React Native application was fully inspected (not from docs alone). Files read include:
`app/_layout.tsx`, all tab screens, all stack/modal screens (add-transaction, goals, calendar,
categories, payees, groups, quick-transactions, daily-limit-detail), all 11 report routes (inventoried),
`src/db/*` (schema, migrations, all query modules), `src/services/*` (dashboard, transaction, budget,
goal, report, calendar, group, notification) , `src/services/sync/*` (all 7 entity sync modules +
coordinator), `src/store/*`, key hooks (`useAppSettings`, `useBiometrics`, `useDashboardData`,
`useDashboardSync`), `src/utils/*` (validators, formatters, dataMappers, transactionTimestamp,
dateUtils), `src/models/types.ts`, `src/constants/*`, `app.json`, `package.json`, and `AI_CONTEXT.md`.

Deliverables produced:

* `Docs/MACOS_FEATURE_MATRIX.md` — complete feature inventory with macOS equivalents (Phases 1–2).
* `Docs/MACOS_ARCHITECTURE.md` — target macOS architecture (Phase 3).
* `Docs/DATA_ARCHITECTURE.md` — schema, sync protocol, business rules, persistence decision (Phase 3).

Verification:

* No CSV/JSON export exists in the RN code despite README claims (documented as new macOS feature).
* `ajv` dependency is unused; no macOS counterpart required.
* Confirmed `resetAppData` does not delete `quick_transactions` (parity quirk, documented).

Build status: `BUILD SUCCEEDED` (Debug, verified 2026-09-20 after docs update).

### Phase 1 Verification Pass (second agent, 2026-09-20)

A second agent independently re-verified the analysis by reading the actual RN source — all 7 sync
modules, all 8 query modules, `database.ts`, every service, the key hooks, all utils/models/
constants, `package.json`, and the main screens. **Verdict: the Phase 1 documentation is accurate**;
schema, sync protocol, formulas, validators, feature inventory, and quirks all match the code.

New findings folded into the docs (all now in `DATA_ARCHITECTURE.md` §2–§4, §7, §8):

1. `is_living_cost` is **local-only** (stripped from push, omitted from pull insert) → resets to 0
   after every pull; Living Costs report silently loses its selection after sync.
2. Budget push normalizes interval `Monthly`→`Month` and **silently skips** budgets with empty
   category arrays (they remain dirty forever).
3. Quick-transactions pull deletes only `deleted = 0` rows (other meta entities delete all).
4. Group last-sync key mismatch: `groupService` uses `@last_sync_groups_`, `groupSync` uses
   `@last_sync_transaction_groups_`.
5. `transaction_timestamp` is written as **UTC** ISO at save and converted to local wall-clock only
   at push; `date` on pull is derived from the raw string prefix (docs previously said "ISO local").
6. New categories/payees/groups/quick-transactions auto-assign `priority = MAX(priority)+1`.
7. Reset-data clears an exact, partial list of AsyncStorage keys (now enumerated in the docs); it
   does not clear quick-tx/group sync keys or per-user view-mode keys.
8. Quick-transactions `sync_status` defaults to 1 (born dirty); goals default-sort by name (no
   priority column); `TABLES` also names `profiles`/`attachments`/`sync_log` which are
   Supabase-only (no local tables).

No corrections to the existing feature inventory or architecture decisions were required.

---

## Phase 4 — Native App Shell

**Status:** COMPLETE

Implemented (all builds green, `BUILD SUCCEEDED` + launch smoke test passed):

* `App/JmoneyApp.swift` — `WindowGroup` + `Settings` scene (⌘,) + `AppCommands`; stores injected via
  `.environment` (`.frame(minWidth: 1000, minHeight: 640)`).
* `App/AppState.swift` — `@Observable` shell state: sidebar selection, sheet flags, search-request
  counter (⌘F from any section), status-bar message channel, sync/last-synced fields.
* `App/AppCommands.swift` — File > New Transaction (⌘N), File > Quick Transaction (⌘⇧N),
  Edit > Find… (⌘F), Data > Sync Now (⌘R).
* `Navigation/` — `AppSection` enum (11 destinations, SF Symbols matching the RN tabs),
  `SidebarView` (Finance/Manage/General sections), `RootView` (auth gate + split view + sheets +
  section routing), `StatusBarView` (Finder-style bottom bar: status message + last synced).
* `Features/` — `AuthGateView` (placeholder sign-in with mock session; non-empty validation),
  11 feature views with `ContentUnavailableView` empty states, `NewTransactionSheet` +
  `QuickTransactionPickerSheet` placeholders, `SettingsPaneView` (opens ⌘, window via
  `openSettings`), `SettingsSceneView`.
* `Stores/SessionStore.swift` — mock session (real Supabase + Keychain in Phase 14); sign-out keeps
  local data (RN parity).
* `Support/Formatters.swift` — relative-time helper for the status bar.
* Removed the phase-0 `ContentView.swift` + root `JmoneyApp.swift`; ran `xcodegen generate`.

Design notes for the next agent:

* ⌘F owns the Edit > Find… slot — `TextEditingCommands` is NOT included, so there is no system
  Find conflict. Find presents/focuses the Transactions search field via
  `.searchable(text:isPresented:)` + a `searchRequestID` counter in `AppState`.
* The status bar is the shell's toast/notification surface (replaces RN `ToastContext`); error
  alerts arrive with real flows.
* ⌘R currently reports "Sync isn't connected yet." — swap for the real sync trigger in Phase 14.
* The auth gate is a mock; keep `SessionStore`'s public surface (isAuthenticated/userEmail/signOut)
  when replacing internals with Supabase.

# Phase Status

| Phase | Description                         | Status      |
| ----- | ----------------------------------- | ----------- |
| 0     | Project initialization              | COMPLETE    |
| 1     | Analyze React Native application    | COMPLETE    |
| 2     | Feature inventory                   | COMPLETE    |
| 3     | macOS architecture                  | COMPLETE    |
| 4     | Native app shell                    | COMPLETE    |
| 5     | Data layer                          | COMPLETE    |
| 6     | Dashboard                           | COMPLETE    |
| 7     | Transactions                        | COMPLETE    |
| 8     | Budgets                             | COMPLETE    |
| 9     | Goals                               | COMPLETE    |
| 10    | Reports                             | NOT STARTED |
| 11    | Calendar                            | NOT STARTED |
| 12    | Categories / Payees / Groups        | NOT STARTED |
| 13    | Settings                            | NOT STARTED |
| 14    | Authentication / Sync               | NOT STARTED |
| 15    | Import / Export                     | NOT STARTED |
| 16    | macOS commands / keyboard shortcuts | NOT STARTED |
| 17    | Accessibility / performance         | NOT STARTED |
| 18    | Final feature parity audit          | NOT STARTED |
| 19    | Release preparation                 | NOT STARTED |

---

# Current Phase

**Phase:** 10 — Reports

Phase 9 (Goals) is complete, built, and tested (200 tests green — see the Progress Log).

Goal: the Reports area — the report index plus the 11 report types and their drill-downs, all
reusing the shared row renderers and the read-path service pattern.

1. Read `MACOS_FEATURE_MATRIX.md` §7 for the full report inventory (11 report types plus the type
   toggle, period selectors, comparison column, drill-down, search/sort) and `DATA_ARCHITECTURE.md`
   §2 for the comparison formula (diff% = (current − previous) / previous × 100, previous matched by
   name/type, MTD-vs-MTD or YTD-vs-YTD for the current period and full-vs-full otherwise, new items
   with no previous showing +100%).
2. This is the largest read-only phase: `src/services/reportService.ts` (267 lines) plus
   `src/db/reportQueries.ts` (395) are the specification. The screens are the `app/reports/` folder
   (`monthly-summary`, `yearly-summary`, `category-summary`, `payee-summary`, `group-summary`,
   `yearly-category`, `yearly-payee`, `living-costs`, `subscription-bills`, `payee-overview`,
   `category-overview`) with the shared pieces in `src/components/reports/` (`ReportListItem`,
   `ReportSummary`, `ReportSelectors`, `ReportSortPicker`, `ReportDrillDownModal`,
   `ReportEmptyState`, `ReportConfigModal`).
3. `Services/ReportService.swift` — port the pure calculations (`reportTypes` config,
   `processSummary`, the comparison maths, the "Subscription"/"Bills" name match, the
   `is_living_cost` filter, the group-priority sort overrides) separately from the parameterized
   queries, so the whole phase is testable against an in-memory `DatabaseQueue`.
4. `Features/Reports/`: the index (11 cards, view-mode toggle persisted like
   `reports_view_mode` — decide whether to keep that preference in `UserDefaults` and say so), then
   the report pages sharing one row renderer, a type segmented control, period selectors
   (`YearMonthSelector` → the budget `BudgetMonthPicker` is a good starting point), a sort menu, a
   toolbar search field, and the drill-down sheet reusing `TransactionRow`.
5. `AppState.requestedReport` + `ReportDestination` (Phase 6) already records the dashboard
   click-through; Phase 10 must consume it so the dashboard cards land on the right report.
6. Only `transactions`, `categories`, `payees` and `transaction_groups` are read here — no writes,
   so there is nothing to flag for sync.
7. Reuse, don't rebuild: `TransactionRow`, `ProgressBarView`, `AppFormat.currency`,
   `AppState.statusMessage`, and the stable-sort pattern the budgets/goals phases established.

Still outstanding from Phase 7 (documented, not silently dropped — pick these up before the Phase 7
row is treated as fully at parity): location tagging on create plus the location edit sheet;
quick-transaction presets (the bolt FAB / ⌘⇧N picker); Material→SF Symbol category icon mapping
(belongs with Phase 12).

After 10: 11 (Calendar) → remaining phases per the matrix.

---

# Git

The repository is initialized with Git. Every completed phase must have its own Git commit.

Workflow:

```bash
git status
git diff
git add .
git commit -m "<phase-specific message>"
```

Do not commit unrelated changes. Before committing: build, update docs, review the diff.

---

# AI Agent Handoff Rules

Every AI agent must:

1. Read this file first.
2. Inspect the current Git status and latest commits.
3. Determine the current phase.
4. Review `MACOS_FEATURE_MATRIX.md`, `MACOS_ARCHITECTURE.md`, `DATA_ARCHITECTURE.md`.
5. Continue from the current state rather than starting over.
6. Never undo completed functionality without a documented reason.
7. Update this file before finishing its work.
8. Commit completed phases and record the hash below.

---

# Build Requirement

```bash
xcodebuild \
  -project Jmoney.xcodeproj \
  -scheme Jmoney \
  -configuration Debug \
  build
```

Run `xcodegen generate` first if `project.yml` changed.
A phase should not be marked COMPLETE if the project does not build.

---

# Progress Log

## Phase 0

**Status:** COMPLETE

The initial native macOS project was created and verified (`BUILD SUCCEEDED`).

## Phase 1 (with Phases 2–3 deliverables)

**Status:** COMPLETE (2026-09-20)

### What was done

* Inspected the React Native source in depth: navigation, every screen, DB schema/queries, services,
  sync engine, auth, settings, validation, formatting, and date handling.
* Produced `MACOS_FEATURE_MATRIX.md`: 12 sections, every RN feature inventoried with its planned
  macOS equivalent and status. Nothing silently dropped; justified omissions noted (haptics,
  keep-awake; CSV/JSON export does not exist in RN and is planned as a macOS addition).
* Produced `MACOS_ARCHITECTURE.md`: SwiftUI + `@Observable` MVVM, GRDB persistence,
  supabase-swift, sidebar navigation, mobile→Mac interaction mapping, performance strategy.
* Produced `DATA_ARCHITECTURE.md`: exact local schema, sync protocol (push `sync_status=1`,
  full-replace pulls for meta entities, incremental `tid`-cursor pulls for transactions, force
  resync), business-rule formulas (daily limit, net worth, report comparisons, validation bounds),
  AsyncStorage key inventory, and the persistence decision with rationale.
* Verified the macOS project still builds (`BUILD SUCCEEDED`).
* **Verification pass (second agent):** re-read the RN source end-to-end and confirmed the
  documentation; 8 previously undocumented quirks discovered and folded into
  `DATA_ARCHITECTURE.md` (see the Phase 1 section above for the list).

### Key findings the next agent must know

1. **Business logic lives in SQL** (`src/db/reportQueries.ts`, `transactionQueries.ts`) plus pure
   functions in services. Reproduce formulas exactly — they are tabulated in
   `DATA_ARCHITECTURE.md` §2.
2. **Sync protocol is specific**: `sync_status` 1=dirty; pushes upsert-by-id; deletes push remote
   delete then hard-delete locally; meta entities full-replace on pull; transactions pull
   incrementally by server `tid` in 1000-row chunks; force-resync wipes local transactions first.
3. **Denormalized columns**: transactions store `category_name/icon/app_icon`, `payee_name/logo`,
   `group_name` copies; must be maintained on save and populated via joins on pull.
4. **Timestamp semantics**: `transaction_timestamp` ISO-local; `date` derived `yyyy-MM-dd`; Supabase
   push strips the timezone suffix. See `DATA_ARCHITECTURE.md` §7.
5. **Quirks to preserve (or explicitly flag)**: `resetAppData` skips `quick_transactions`;
   group delete leaves dangling `group_id` values; old rows can contain literal `'null'` ids which
   queries filter out; RN interpolates strings into SQL (macOS must parameterize).
6. **Currency** is ₹ (en-IN). Theme palette is iOS-system-like; keep light/dark support.
7. **Second-pass quirks (must-read before implementing sync/categories/budgets)**: `is_living_cost`
   is local-only and resets on pull; empty-category budgets are never pushed; timestamps are UTC at
   save, local wall-clock at push; new meta entities auto-assign priority `MAX+1`. Full list in
   `DATA_ARCHITECTURE.md` §2–§4 and §8.

### Issues / deviations

* None blocking. The macOS docs contain two intentional forward decisions (export feature in Phase
  15; parameterized SQL replacing RN string interpolation) — both documented.

## Phase 4 — Native App Shell

**Status:** COMPLETE (2026-09-20)

### What was done

* Built the full shell per `MACOS_ARCHITECTURE.md` §3: `WindowGroup` + `Settings` scene + `Commands`,
  `NavigationSplitView` sidebar (Finance/Manage/General sections hosting all 11 areas), section
  routing, and a Finder-style bottom status bar (status message + "Last synced").
* Wired menu commands: File > New Transaction (⌘N), File > Quick Transaction (⌘⇧N), Edit > Find…
  (⌘F presents/focuses the Transactions search field via `.searchable(text:isPresented:)`),
  Data > Sync Now (⌘R, placeholder until the sync engine exists).
* Every feature area has a native `ContentUnavailableView` empty state; Transactions adds an
  empty-state "New Transaction" action button; Settings pane opens the ⌘, window via
  `@Environment(\.openSettings)`.
* Auth gate placeholder with mock session (`SessionStore`); sign-in validates non-empty email +
  password (mirrors the RN login's minimal validation). Real Supabase auth stays in Phase 14.
* Removed phase-0 `ContentView.swift`/root `JmoneyApp.swift`; ran `xcodegen generate` (required —
  XcodeGen projects reference files explicitly, so any file add/remove needs regeneration).

### Verification

* `BUILD SUCCEEDED` (Debug) with no compile warnings.
* Launch smoke test: app opened from the built product, ran (process alive after 4 s), quit cleanly.

### Issues / deviations

* SwiftUI has no `CommandGroupPlacement.find`; ⌘F is registered on Edit > Find… via
  `CommandGroup(after: .pasteboard)`. Because `TextEditingCommands` is not included, SwiftUI's
  default Edit menu has no Find submenu and the shortcut is conflict-free.
* ⌘R currently reports "Sync isn't connected yet." via the status bar (honest placeholder).

## Phase 5 — Data Layer

**Status:** COMPLETE (2026-09-20)

### What was done

* `project.yml`: added the GRDB.swift SPM package (`from: "7.0.0"`), a `JmoneyTests` unit-test
  target, and an explicit `Jmoney` scheme with a test action. Ran `xcodegen generate`.
* `Services/DatabaseService.swift`: `@Observable` service owning a WAL `DatabasePool`
  (Application Support/Jmoney/jmoney.db) and `DatabaseMigrator` v1 that creates the exact RN
  schema — all 7 tables, every column + default, and all 11 indexes (incl. composite column order).
  The v1 migration creates the final schema directly; fresh installs skip the RN app's incremental
  ALTER history (net-identical). `prepare()` is idempotent and called from `RootView.task`,
  mirroring the RN boot order (`initDB()` before navigation); status bar reports readiness/failure.
* `Models/`: 7 DTOs (`Transaction`, `Goal`, `Budget`, `Category`, `Payee`, `QuickTransaction`,
  `TransactionGroup`) with column names identical to the RN schema via explicit `CodingKeys`;
  documented quirks inline (denormalized name columns, local-only `is_living_cost`, born-dirty
  quick transactions, no goal priority).
* `Support/Timestamps.swift`: byte-compatible port of `transactionTimestamp.ts` — suffix detection,
  UTC→local wall-clock conversion on push, first-space→`T` replacement, prefix-based day
  extraction, JS `new Date` fallbacks (lowercase `t`/`z`, no-colon offsets, date-only = UTC
  midnight), `split('T')[0]` fallback. `timeZone` parameter (default `.current`) enables
  deterministic tests.
* `JmoneyTests/` (21 tests, all green): schema/tables/columns/defaults/indexes, quick-transactions
  born-dirty quirk, migration idempotency, DTO round-trips incl. NULL columns, timestamp rules
  with fixed timezones.

### Verification

* `xcodebuild … build` → `BUILD SUCCEEDED`; `xcodebuild … test -destination 'platform=macOS'` →
  `TEST SUCCEEDED` (21 tests, 0 failures).
* Launch smoke test: app ran, DB created at `~/Library/Application Support/Jmoney/jmoney.db` with
  WAL sidecar files; `sqlite3` confirmed all 7 tables + `grdb_migrations`.

### Issues / deviations

* GRDB's `MutablePersistableRecord.insert` is `mutating` — test records must be `var`.
* Two timestamp tests caught real port bugs before commit (colon insertion point for `+0200`
  offsets; lowercase `t` separator) — fixed; tests are doing their job.
* GRDB adds a `grdb_migrations` table absent in RN — internal bookkeeping, not a parity concern.

## Phase 6 — Dashboard

**Status:** COMPLETE (2026-09-21)

### What was done

* `Services/DashboardService.swift` — pure ports of `dashboardService.ts` (`processSummary`,
  `calculateDailyLimit`, `calculatePayDayInfo`, `subtracting`, `dateWindows`) plus the four SQL
  helpers from `reportQueries.ts`/`transactionQueries.ts` (`incomeExpenseSummary`,
  `expensesByCategory`, `netWorth`, `spentToday`), `transactions(userId:date:)` for the drill-down,
  and `fetchMetrics`. Every query is parameterized and preserves the per-user + `deleted = 0` scoping.
* `Features/Dashboard/DashboardViewModel.swift` — `@Observable`; loads all seven metrics in a single
  `pool.read` and stores the `referenceDate` the calculations were made against.
* Widgets in `Features/Dashboard/`: `DashboardCard` (shared container), `DailyLimitCard`,
  `RemainingCard`, `PayDayCard`, `TopCategoriesCard`, `SummaryCard` (This Month / This Year),
  `NetWorthCard`, plus `TodaysActivityView` (the `daily-limit-detail` drill-down as a sheet). The RN
  vertical card scroll becomes a two-column `Grid` with net worth spanning both columns.
* Click-through: Daily Limit → Today's Activity; Pay Day → Calendar section; Top Categories →
  Transactions By Category; This Month/This Year → the matching summary report. Reports are still a
  placeholder, so the destination is carried on `AppState.requestedReport` via the new
  `ReportDestination` enum and echoed by `ReportsView` until Phase 10 builds the pages.
* `Support/ProgressViews.swift` — `CircularProgressView` + `ProgressBarView` (native; see the
  Decision Log for the ring change).
* `Support/Formatters.swift` — added `AppFormat.currency` (₹, `en-IN` grouping, 0 or 2 fraction
  digits, sign dropped) and the English date-pattern helpers the dashboard needs.
* `Stores/SessionStore.swift` — added `userId` (mock placeholder id) so the per-user queries are
  exercised; plus `AppState.openReport(_:)`.
* Tests, 21 new (63 total): `DashboardCalculationTests` (23), `DashboardQueryTests` (7),
  `FormatterTests` (9), `DashboardViewRenderingTests` (3 — renders the widget grid and the
  drill-down in their zero-value/empty states through `ImageRenderer`).

### Verification

* `xcodebuild … build` → `BUILD SUCCEEDED`, no warnings.
* `xcodebuild … test -destination 'platform=macOS'` → `TEST SUCCEEDED` (63 tests, 0 failures).
* Launch smoke test: the built app ran for 5 s and quit cleanly.
* The tests caught a real bug before commit: `DashboardService.subtracting` *added* instead of
  subtracting months/years, which shifted every previous-period window by two months (or a year).
  Fixed; the clamping tests (Mar 31 → Feb 28, Feb 29 → Feb 28) now pass.

### Issues / deviations

* One test expectation was wrong rather than the code: year-to-date legitimately includes the
  August rows — the Aug 25 row is only excluded from the *MTD comparison* window.
* `AppFormat.currency` deliberately reproduces the source's sign-dropping (negative amounts render
  as their magnitude; colour conveys direction).
* The RN drill-down renders `TransactionCard`; the macOS sheet uses a lightweight row until Phase 7
  builds the real transaction list (Phase 7 should replace it with the shared row).

## Phase 7 — Transactions

**Status:** COMPLETE (2026-09-21)

### What was done

* `Services/TransactionService.swift` — ports `transactionService.ts` + `transactionQueries.ts` +
  `getMonthlyFilteredStats`: `Filters` (search, category/payee/group ids, date range), the
  `mapTransactionsToFlashList` section mapping (`sections(from:)` — day groups newest-first, rows
  within a day by timestamp newest-first, per-day nets and the overall net), `transactions(list)`,
  `list`, `monthlyStatistics` (last five months, current first), `lookups`, `save`, `softDelete`,
  and `makeTransaction` (the `handleSave` port). Every query is parameterized; per-user and
  `deleted = 0` scoping is preserved.
* `Support/Validators.swift` — `validateAmount` / `validateTransaction` ports with the source's
  field order preserved so the "first error" matches.
* `Support/Timestamps.swift` — added `instant(from:)` (the JS `new Date(ts).getTime()` used for
  ordering) and `utcISOString(from:)` (JS `toISOString()`, used when saving).
* `Support/Formatters.swift` — added `monthDayYear`, `dayMonth`, `preciseTimestamp` (`PPp`) and
  `date(fromYearMonthDay:)`.
* `Features/Transactions/`: `TransactionsViewModel`, `TransactionEditorViewModel`,
  `TransactionRow` (+ `TransactionDayHeader`), `TransactionsView`, `TransactionEditorView`,
  `TransactionFilterPopovers` (date range, multi-select, last-5-months stats), and
  `TransactionEditorTarget`. `NewTransactionSheet` (the Phase 4 placeholder) was deleted.
* `AppState` — `transactionEditor` target (drives the editor sheet from ⌘N or a row) plus
  `dataRevision` / `markDataChanged()`, the native replacement for the RN
  `DeviceEventEmitter 'module_refreshed'` events; Dashboard and Transactions both reload on it.
* `TransactionRow` is now shared with the dashboard's Today's Activity drill-down.
* `Transaction`, `Category`, `Payee`, `TransactionGroup` conform to `Identifiable` for SwiftUI
  lists/pickers.
* Tests, 48 new (111 total): `TransactionFilterTests` (23 — filters, the numeric-vs-LIKE search
  split, Monday-started week presets, section grouping/ordering/nets, validation and first-error
  order) and `TransactionServiceTests` (25 — SQL scoping/ordering, both search branches, entity and
  date filters, sections, the five-month statistics including the LIKE-only stats search, lookups,
  soft delete, upsert-in-place, and the editor view model).

### Verification

* `xcodebuild … build` → `BUILD SUCCEEDED`, no warnings.
* `xcodebuild … test -destination 'platform=macOS'` → `TEST SUCCEEDED` (111 tests, 0 failures).
* Launch smoke test: the built app ran for 5 s and quit cleanly.
* The tests caught a real bug before commit: the statistics search was reusing the list query's
  numeric-amount branch, so a search of `50` only matched `amount = 50` instead of the source's
  LIKE over description and amount-as-text (it must match "500 note electricity" too). The stats
  path now has its own LIKE-only predicate. Three wrong test expectations were also corrected
  (a seeded-fixture helper that never seeded, an inclusive `date <=` bound, and a preserved `tid`).

### Issues / deviations

* Search and filter values are **bound parameters**; the RN code interpolates them into SQL.
  Results are identical, and `%`/`_` still behave as LIKE wildcards.
* A non-numeric amount is rejected. JS `parseFloat('1,234')` returns `1`, which would silently save
  ₹1 — a deliberate, documented deviation (`Validators.amountError`).
* Every validation error is shown inline next to its field; the RN screen surfaces only the first
  one as a toast. Rules and messages are unchanged.
* Bottom sheets became toolbar popovers, and the RN icon-tile multi-select became a checkbox list.
* The FlashList pinned/sticky date headers are not reproduced; the list uses native `List` sections
  with per-day headers, which also brings native selection, keyboard navigation and ⌫.
* The RN row's "not yet uploaded" cloud badge is omitted while the sync engine does not exist (every
  row would be flagged). Category glyphs use a neutral SF Symbol because the stored
  `category_app_icon` values are Material icon names.
* Editing never drops saved coordinates: latitude/longitude are preserved on save and shown
  read-only in the editor until location tagging is implemented.

---

## Phase 8 — Budgets

**Status:** COMPLETE (2026-09-21)

### What was done

* `Services/BudgetService.swift` — ports `budgetService.ts` + `budgetQueries.ts`:
  `EnrichedBudget`, `SortKey`, `MonthRange`, `CardInfo`, the pure calculations
  (`cardInfo` + advice text, `daysRemaining`, `todayProgress`, `daysInMonth`, `monthRange`,
  `isCurrentMonth`, `canGoToPreviousMonth`/`canGoToNextMonth`, `isMonthSelectable`,
  `selectableYears`), the `categories` JSON codec, the stable `sorted` comparator, and the queries
  (`budgets`, `spending`, `budgetsWithSpending`, `transactions`, `drillDown`, `minTransactionDate`,
  `expenseCategories`, `save`, `softDelete`). Every query is parameterized (the RN code interpolates
  the user id); per-user and `deleted = 0` scoping is preserved.
* `Support/Validators.swift` — added `validateBudget` with the source's `name` → `categories` →
  `amount` field order (which decides the first error) and its exact messages.
* `Support/Formatters.swift` — added `monthAbbrevDay` (`MMM d`), `monthAbbrevYear` (`MMM yyyy`) and
  `monthYear` (`MMMM yyyy`) for the budget period labels.
* `Features/Budgets/`: `BudgetsViewModel`, `BudgetEditorViewModel`, `BudgetEditorTarget`,
  `BudgetRow` (+ the pace bar), `BudgetsView`, `BudgetEditorView`, `BudgetMonthPicker`,
  `BudgetDrillDownView`. The Phase 4 `BudgetsView` placeholder was replaced.
* `BudgetsViewModel.shouldRunInitialSync` keeps the RN screen's first-open auto-sync condition as a
  pure predicate (including the `!lastSync.includes('T')` test) for Phase 14 to call.
* Tests, 54 new (165 total): `BudgetCalculationTests` (29 — card percentage/overspend/advice edge
  cases, per-day flooring, the source's own "1 more days" wording, days-remaining and today-progress
  maths, leap February, month-range navigation bounds, the year list, the initial-sync predicate,
  and `validateBudget` including first-error order) and `BudgetServiceTests` (20 — scoping,
  the spending aggregate's type/range/deleted rules, enrichment, all four sorts plus stability,
  defensive category-JSON decoding, the drill-down's type behaviour, `minTransactionDate` and its
  no-history fallback, expense-category lookup, insert/upsert/soft-delete write paths) plus
  `BudgetsViewRenderingTests` (5 — render smoke for the list, both editor modes and the drill-down).

### Verification

* `xcodebuild … build` → `BUILD SUCCEEDED`, no warnings.
* `xcodebuild … test -destination 'platform=macOS'` → `TEST SUCCEEDED` (165 tests, 0 failures).
* Launch smoke test: the built app ran for 5 s and quit cleanly.
* Two test-harness bugs were caught and fixed while writing the suite: the fixture seeded inside a
  read transaction (SQLite error 8, "attempt to write a readonly database"), which is exactly the
  kind of mistake a shared read-only fixture helper now prevents.

### Issues / deviations

* Budget list rows are native `List` rows rather than a phone card column; the card's figures,
  advice line, percentage badge, per-day ticks and today marker are all preserved.
* The RN category chip row became a checkbox list in the editor (the Phase 7 precedent for the same
  multi-select), and the RN bottom sheets became a sheet (editor) and a popover (period picker).
* `selectedMonth` is normalized to the first instant of the month. This removes an RN quirk rather
  than reproducing it: JS `setMonth` overflow-rolls, so picking "February" from Jan 31 lands on
  Mar 3. Every other use of the RN `selectedDate` was already month-boundary based.
* Dropping a *no-longer-expense* category from an edited budget is **not** done: the source keeps it
  in `form.categories` and writes it back, so the selection is saved as-is (the picker simply cannot
  render it as a chip).
* The RN header's manual sync button is not reproduced — there is no sync engine until Phase 14.
  New Budget has no key equivalent yet; Phase 16 owns the shortcut set.

---

## Phase 9 — Goals

**Status:** COMPLETE (2026-09-21)

### What was done

* `Services/GoalService.swift` — ports `goalService.ts` plus `insertGoal`/
  `deleteGoalAsync` from `metaQueries.ts` and the progress maths in `GoalCard.tsx`:
  `CardInfo` (`rawProgress`, clamped `progress`, rounded `percentage`, `remaining`
  floored at 0, `isComplete` by the clamped value), `progressRatio`, the stable
  `sorted` comparator for the three modes, and the queries (`goals`, `list`,
  `save`, `softDelete`). User and `deleted = 0` scoping preserved; the list orders
  by name before sorting.
* `Support/InitialSyncGuard.swift` — **new shared predicate**. The goals and budgets
  screens carry byte-identical first-open sync logic apart from their storage keys,
  so the condition now lives in one place instead of being copied.
  `BudgetsViewModel.shouldRunInitialSync` and `GoalsViewModel.shouldRunInitialSync`
  are thin named wrappers over it (the budget one keeps its Phase 8 name so that
  phase's docs and tests stay valid).
* `Support/Validators.swift` — added `validateGoal` with the source's `name` →
  `targetAmount` → `currentAmount` field order and its exact messages.
* `Models/Goal.swift` — `Identifiable` conformance for SwiftUI lists.
* `Features/Goals/`: `GoalsViewModel`, `GoalEditorViewModel`, `GoalEditorTarget`,
  `GoalRow`, `GoalsView`, `GoalEditorView`. The Phase 4 `GoalsView` placeholder was
  replaced.
* Tests, 35 new (200 total): `GoalCalculationTests` (21 — card progress/rounding/
  clamping/over-funding, the unclamped ratio, all three sorts plus stability, the
  sort-toggle and caption behaviour, the sync guard including a direct comparison
  against `InitialSyncGuard`, and `validateGoal` including the empty-current-amount
  quirk) and `GoalServiceTests` (7 — scoping, ordering, the sorted list, insert and
  in-place upsert, soft delete and its user scoping) plus `GoalsViewRenderingTests`
  (7 — render smoke for the list, both editor modes and both row logo states, plus
  the view model/editor defaults).

### Verification

* `xcodebuild … build` → `BUILD SUCCEEDED`, no warnings.
* `xcodebuild … test -destination 'platform=macOS'` → `TEST SUCCEEDED` (200 tests, 0 failures).
* Launch smoke test: the built app ran for 5 s and quit cleanly.
* The green suite includes the earlier phases, so the `InitialSyncGuard` extraction
  and the `Goal` model change did not regress Phases 5–8.

### Issues / deviations

* The RN screen's header title ("Savings Goals") becomes the window title and its
  sort caption moves to a bar above the list; the sort sheet becomes a toolbar menu.
* The save button stays enabled so the name error is reachable inline. In the RN
  modal the button is disabled while the name is empty, which makes its own
  "Goal name is required" message unreachable.
* The empty "Currently Saved" field really is an error, not a missing-required-field
  oversight in this port: `parseFloat('')` is `NaN` in JS, whose `isNaN` branch
  carries the "Current amount cannot be negative" message. Preserved verbatim, so a
  new goal needs an explicit `0`.
* A non-numeric amount is rejected rather than `parseFloat`-truncated, the same
  documented deviation as `amountError`.
* `GoalCard`'s remote logo (`logo.startsWith('http')`) is fetched with `AsyncImage`;
  anything else falls back to the 🎯 placeholder tile.
* The RN header's manual sync button is not reproduced, and Add New Goal has no key
  equivalent yet (Phase 16).

---

# Decision Log

| Date       | Decision                                                   | Reason                                    | Agent         |
| ---------- | ---------------------------------------------------------- | ----------------------------------------- | ------------- |
| 2026-09-20 | Native SwiftUI macOS application                           | Proper native Mac experience              | Initial setup |
| 2026-09-20 | Existing React Native app remains reference implementation | Preserve functionality and business rules | Initial setup |
| 2026-09-20 | XcodeGen used for project generation                       | Reproducible project configuration        | Initial setup |
| 2026-09-20 | SQLite via GRDB.swift, schema mirrored from RN app         | Proven SQL aggregations; sync protocol fidelity; offline-first performance (SwiftData/Core Data rejected) | Phase 1 |
| 2026-09-20 | supabase-swift + Keychain session storage                  | Same backend/auth as RN; secrets from build config, never in source | Phase 1 |
| 2026-09-20 | MVVM with `@Observable`; GRDB `ValueObservation` for reactive data | Testable business logic; replaces RN `DeviceEventEmitter` refresh events | Phase 1 |
| 2026-09-20 | Sidebar navigation hosting all areas                       | Native Mac equivalent of tabs + stack screens | Phase 1 |
| 2026-09-20 | Deployment target macOS 14+                                | `@Observable`, modern NavigationSplitView | Phase 1 |
| 2026-09-20 | Bottom status bar as the shell's status/toast surface       | Native Mac pattern replacing RN toasts + "Synced Xm ago" subtitle | Phase 4 |
| 2026-09-20 | Mock session behind `SessionStore` until Phase 14           | Auth gate exercised end-to-end without blocking shell work | Phase 4 |
| 2026-09-20 | ⌘F via Edit > Find… (`CommandGroup(after: .pasteboard)`)    | SwiftUI default Edit menu has no Find submenu (no `TextEditingCommands`), so the shortcut is conflict-free | Phase 4 |
| 2026-09-20 | `ContentUnavailableView` for all feature empty states       | Native macOS 14 empty-state component; a11y for free | Phase 4 |
| 2026-09-20 | GRDB.swift 7.x via SPM; explicit `Jmoney` scheme with tests | Current stable line; reproducible builds; `xcodebuild test` works | Phase 5 |
| 2026-09-20 | v1 migration builds the final schema directly               | Fresh installs skip the RN app's incremental ALTER history; net-identical, testable | Phase 5 |
| 2026-09-20 | `timeZone` parameter on timestamp ports (default `.current`)| Same behavior as JS device-local time, but deterministically testable | Phase 5 |
| 2026-09-21 | Daily-limit `remainingDays` = `daysInMonth − currentDay + 1`       | Identical to RN's `differenceInDays(endOfMonth(today), today) + 1`, but calendar-exact and testable | Phase 6 |
| 2026-09-21 | date-fns month/year clamping implemented explicitly (`DashboardService.subtracting`) | Foundation's date arithmetic rolls overflow into the next month; date-fns clamps (Mar 31 − 1 month = Feb 28) | Phase 6 |
| 2026-09-21 | All seven dashboard queries share one `pool.read`                  | Same values from a single consistent snapshot instead of seven independent ones | Phase 6 |
| 2026-09-21 | Native arc progress ring replaces the RN four-segment border ring  | macOS has real path stroking; percentage/value/label inputs are unchanged (MACOS EQUIVALENT) | Phase 6 |
| 2026-09-21 | Dashboard uses a two-column `Grid` (net worth spans both)          | Uses the desktop window width; widgets stay comparable at a glance | Phase 6 |
| 2026-09-21 | Report click-through recorded on `AppState.requestedReport`        | Dashboard can link to reports before Phase 10 builds the pages | Phase 6 |
| 2026-09-21 | `AppFormat.currency` keeps the source's sign-dropping behavior     | Parity with `formatCurrency`; the alternative would silently change every displayed amount | Phase 6 |
| 2026-09-21 | Transaction filters/search build SQL with bound parameters          | The RN code interpolates user input into SQL; parameterizing removes injection risk without changing results | Phase 7 |
| 2026-09-21 | A non-numeric amount is rejected instead of `parseFloat`-truncated  | JS `parseFloat('1,234')` is 1 and would silently save ₹1 | Phase 7 |
| 2026-09-21 | All validation errors shown inline (not just the first as a toast)  | Native macOS form treatment; rules and messages are the RN ones | Phase 7 |
| 2026-09-21 | Filter sheets → toolbar popovers; icon grid → checkbox list         | Native macOS reading of the same multi-select behaviour | Phase 7 |
| 2026-09-21 | Native `List` sections instead of FlashList pinned headers         | Brings native selection, keyboard navigation and ⌫ for free; per-day headers and totals are kept | Phase 7 |
| 2026-09-21 | `AppState.dataRevision` replaces `DeviceEventEmitter module_refreshed` | One observable counter reloads every open view after a write | Phase 7 |
| 2026-09-21 | The editor preserves `latitude`/`longitude` on edit                 | Location tagging is not built yet; dropping saved coordinates would lose data | Phase 7 |
| 2026-09-21 | `selectedMonth` is normalized to the first of the month             | Removes the JS `setMonth` overflow quirk (Jan 31 → "February" landed on Mar 3); every other RN use of `selectedDate` was already month-boundary based | Phase 8 |
| 2026-09-21 | Budget sorting is explicitly stable                                | JS `Array.prototype.sort` is stable and Swift's `sorted(by:)` is not, so ties are restored to the `ORDER BY name` order | Phase 8 |
| 2026-09-21 | Budget name sort uses locale collation (`localizedCompare`)          | Matches the intent of JS `localeCompare`; exact ordering of case-differing names can still differ between ICU and JSCollator | Phase 8 |
| 2026-09-21 | The pace bar keeps its day ticks and today marker                  | They are the card's information (spend vs. month pace), not decoration; drawn in one `Canvas` pass instead of ~31 overlaid views | Phase 8 |
| 2026-09-21 | A no-longer-expense category stays in an edited budget's selection  | The RN modal cannot render it as a chip but does write it back; dropping it would silently lose data | Phase 8 |
| 2026-09-21 | The first-open budget sync guard is a pure predicate                | No sync engine until Phase 14; the predicate encodes the source's `!lastSync.includes('T')` test so the engine can call it unchanged | Phase 8 |
| 2026-09-21 | New Budget ships without a key equivalent                          | ⌘N/⌘⇧N belong to transactions; Phase 16 owns the shortcut set | Phase 8 |
| 2026-09-21 | The first-open sync condition is shared (`InitialSyncGuard`)       | Goals and budgets carry byte-identical logic; one implementation beats two copies, and each phase keeps its own thin named wrapper | Phase 9 |
| 2026-09-21 | Goal sort captions the raw value ("Amount") but the menu says "Target Amount" | Preserves the source's own discrepancy between its caption and its sort sheet | Phase 9 |
| 2026-09-21 | An empty "Currently Saved" is an error, not a missing required field | `parseFloat('')` is `NaN` in the source, whose message is "Current amount cannot be negative" — preserved so the rules stay identical | Phase 9 |
| 2026-09-21 | The goal save button stays enabled                              | The RN modal disables it while the name is empty, which makes its own name error unreachable; inline errors need the button pressable | Phase 9 |
| 2026-09-21 | Goal logos use `AsyncImage` for `http` URLs, else the 🎯 tile   | Mirrors `logo.startsWith('http')`; anything else (including '') gets the placeholder | Phase 9 |

---

# Known Issues

* None in the macOS project. (RN-side observations that constrain the port are listed in
  `DATA_ARCHITECTURE.md` §7 — they are parity constraints, not defects to fix silently.)

---

# Next Agent Instructions

Phases 4–9 are complete and green (200 tests). Start **Phase 10 (Reports)** — full instructions in
the "Current Phase" section above, which also lists the Phase 7 items still outstanding (location
tagging, quick-transaction presets, category icon mapping).

Existing infrastructure (don't redo):

* `DatabaseService` (`@Observable`, `.environment`-injected; `prepare()` idempotent from
  `RootView.task`). Pool access: `database.pool` after `prepare()`, error in `initializationError`.
* DTOs in `Models/` map columns 1:1; `Transaction` carries the denormalized name columns.
* `TransactionTimestamp` (`Support/Timestamps.swift`) for all timestamp derivations — do not
  re-implement with different semantics.
* `DashboardService` is the reference service pattern: pure static calculations plus parameterized
  GRDB queries that take a `Database`, so everything is testable against an in-memory
  `DatabaseQueue`. Follow it for `TransactionService` and the rest.
* `AppFormat` (`Support/Formatters.swift`) for currency (₹/en-IN) and English date patterns.
* `ProgressBarView` / `CircularProgressView` (`Support/ProgressViews.swift`) are reusable.
* `SessionStore.userId` is the mock user id to scope per-user queries by; `AppState.openReport(_:)`
  + `ReportDestination` handle cross-section links.
* `TransactionService` is the reference for entity work: `Filters` in, parameterized queries out,
  with a `Draft` → row factory for writes. Its tests show the in-memory `DatabaseQueue` fixture
  pattern — seed with a shared helper through `dbQueue.write`, then assert inside `dbQueue.read`
  (seeding inside a read transaction fails with SQLite error 8).
* `BudgetService` / `GoalService` are the closest references for the remaining entity phases (the
  meta entities): a list query, a per-row enrichment aggregate where needed, a stable sorted
  comparator, and `save`/`softDelete`. Their view models show the observed-sort reload pattern, and
  `InitialSyncGuard` is where any further first-open sync predicate belongs (Phase 14).
* Reports (Phase 10) is read-only: follow the same service shape but skip the write path. Its RN
  specification is `reportService.ts` + `reportQueries.ts` + the `app/reports/` screens.
* `Validators` (amount/transaction/budget/goal) and `Support/Formatters.swift` cover the shared
  formatting and validation rules; extend rather than duplicate.
* `AppState.dataRevision` / `markDataChanged()` is how a write tells open views to reload;
  `AppState.statusMessage` is the toast surface the RN screens use `showToast` for.
* `TransactionRow` is shared with the dashboard and the budget drill-down; keep new list renderers
  consistent with it.
* Tests: `JmoneyTests/` via `xcodebuild … test -destination 'platform=macOS'` (200 passing).
* Do not re-analyze the RN app from scratch — this file plus the three docs are the analysis record.

### Phase 1 Commit

`6b1f36d` — 2026-09-20 — "phase: analyze existing application" (recorded in a follow-up docs commit;
the hash refers to the phase commit containing the full documentation update).

### Phase 1 Verification Pass Commit

`56a8c37` — 2026-09-20 — "phase: verify source analysis and document sync quirks". The hash below is
recorded in a follow-up docs commit per the established pattern.

### Phase 4 Commit

`d626515` — 2026-09-20 — "phase: add macos app shell" (hash recorded in a follow-up docs commit per
the established pattern).

### Phase 5 Commit

`296a5de` — 2026-09-20 — "phase: add data layer" (hash recorded in a follow-up docs commit per the
established pattern).

### Phase 6 Commit

`fa37991` — 2026-09-21 — "phase: implement dashboard" (hash recorded in a follow-up docs commit per
the established pattern).

### Phase 7 Commit

`f8851fb` — 2026-09-21 — "phase: implement transaction list, filters, search, and editor" (hash
recorded in a follow-up docs commit per the established pattern).

### Phase 8 Commit

`c7ff6c8` — 2026-09-21 — "phase: implement budgets" (hash recorded in a follow-up docs commit per
the established pattern).

### Phase 9 Commit

`8c0ab15` — 2026-09-21 — "phase: implement goals" (hash recorded in a follow-up docs commit per
the established pattern).
