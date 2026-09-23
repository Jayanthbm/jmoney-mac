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
| 10    | Reports                             | COMPLETE    |
| 11    | Calendar                            | COMPLETE    |
| 12    | Categories / Payees / Groups / Quick Transactions | COMPLETE |
| 13    | Settings                            | COMPLETE    |
| 14    | Authentication / Sync               | COMPLETE    |
| 15    | Import / Export                     | COMPLETE    |
| 16    | macOS commands / keyboard shortcuts | COMPLETE    |
| 17    | Accessibility / performance         | NOT STARTED |
| 18    | Final feature parity audit          | NOT STARTED |
| 19    | Release preparation                 | NOT STARTED |

---

# Current Phase

**Phase:** 17 — Accessibility / performance

Phases 0–16 are complete, built, and tested (608 tests green — see the Progress Log).

## Phase 17 brief — Accessibility / performance

The master prompt's §17 (accessibility) and §18 (performance) are one phase. Suggested scope:

1. **Accessibility pass**: audit every custom control for a meaningful
   `accessibilityLabel`/`accessibilityValue` (start with `TransactionRow`, the dashboard cards and
   the progress views, the calendar grid, the quick-transaction cards), mark decorative glyphs
   `accessibilityHidden`, check VoiceOver focus order through the editors (type → amount →
   category…), and confirm every flow is completable with the keyboard alone (⌘N → editor fields →
   Return to save is already the path to verify).
2. **Performance pass**: seed a 10,000-row transaction fixture and verify the list, filters,
   search, dashboard and reports stay responsive (the schema's indexes are already in place —
   confirm queries hit them with `EXPLAIN QUERY PLAN`); keep per-render work out of the views
   (the view models' load-on-revision pattern already does this); confirm large exports run off
   the main thread (they already do — `pool.read` is background).
3. Prefer label/identifier assertions in render tests over timing assertions; performance tests
   that assert wall-clock are flaky and the suite should stay trustworthy.

Also still open: **location tagging** — the one remaining Phase 7 item. `Services/LocationService.swift`
still does not exist; the editor shows saved coordinates read-only and preserves them on save.
Carry it into Phase 17 or a follow-up.

After Phase 17 the remaining phases are 18 (feature-parity audit — flip verified matrix rows to
MACOS EQUIVALENT) and 19 (release preparation).

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

## Phase 10 — Reports

**Status:** COMPLETE (2026-09-21)

### What was done

* `Services/ReportService.swift` — ports `reportService.ts` + the report queries in
  `reportQueries.ts` + the derived state of `useReportData`:
  * **pure**: `previousPeriod` (the comparison windows), `isCurrentPeriod`, `isSameMonth`,
    `applyingComparison` (name/type matching and the diff percentage), `summaryMetrics`,
    `sorted` (search + the three-key comparator), `present` (totals, `totalDiff`, `showTrends`),
    `trend` (the label/appearance decisions), `canStepBack`/`canStepForward`/
    `steppedPeriod`/`showsBackToCurrent`;
  * **queries**: `incomeExpenseSummary`, `monthlyLivingCosts`, `subscriptionBills`,
    `summaryByCategory`, `yearlySummaryByCategory`, `summaryByPayee`, `yearlySummaryByPayee`,
    `monthlySummary`, `yearlySummary`, `payeesOverview`, `categoriesOverview`,
    `summaryByGroup`, `yearlySummaryByGroup`, `groupsOverview`, `categoriesSummaryByGroup`,
    `transactionsByGroupAndCategory`, `aggregatedData`, `transactions`, plus `drillDown` and
    `reportData`. Every query is parameterized (the RN code interpolates the user id, and some
    reports interpolate more), per-user and `deleted = 0` scoped.
  * **one write**: `setLivingCost` (`toggleCategoryLivingCost`) flips `is_living_cost`, a
    **local-only** flag — it is deliberately *not* marked `sync_status = 1`, because the sync layer
    strips that column on push and omits it on pull.
* `Features/Reports/ReportDestination.swift` — the Phase 6 enum grew into the full 11-report
  catalog: titles, descriptions, SF Symbol icons and the index colours from `reportsList`, plus the
  per-report selector flags (`hasTypeToggle`, `showsYear`, `showsMonth`, `isYearly`, `isSummary`,
  `supportsComparison`, `isOverview`, `drillsDownByCategory`) and the two toggle labels.
* `Features/Reports/ReportsViewModel.swift` — the index's grid/list preference (`UserDefaults` under
  the source's `reports_view_mode` key, validated on read) and `ReportDetailViewModel`
  (period/type/sort/search selection, one `pool.read` per load, drill-downs, the living-cost list).
* `Features/Reports/` — `ReportsView` (index + `NavigationStack`), `ReportDetailView` (one
  config-driven page for all eleven reports), `ReportPeriodPicker`, `ReportSummaryView`
  (grid + banner + trend label + empty state), `ReportItemRow` + `ReportGroupRow`,
  `ReportDrillDownView`, `LivingCostConfigView`. The Phase 6 placeholder index is gone.
* `AppState.consumeRequestedReport()` — the dashboard click-through is now consumed by the reports
  section and pushed onto its stack, so a dashboard card lands on its report.
* Tests, 96 new (296 total): `ReportCalculationTests` (the comparison windows incl. the clamping
  cases, diffs, the summary grid, search/sort/stability/priority, totals, trends, period
  navigation, the catalog flags), `ReportServiceTests` (every report query, scoping, the `'null'`
  guards, the living-cost filter and toggle, the comparison pass over the database, all seven
  drill-down variants), `ReportsViewRenderingTests` (index list+grid, all eleven pages, the summary
  grid, the banner, the four row shapes, the group row, both sheets, the empty states, and the view
  model defaults/persistence).

### Verification

* `xcodebuild … clean build` → `BUILD SUCCEEDED`, no warnings.
* `xcodebuild … test -destination 'platform=macOS'` → `TEST SUCCEEDED` (296 tests, 0 failures).
* Launch smoke test: the built app ran for 6 s and quit cleanly.
* The tests caught a real bug before commit: the full-month comparison window's end date was
  computed as `start + 1 month − 1 second`, which lands mid-day on the *first* of the following
  month (the window builder uses noon in the day) — so the "previous month" silently included the
  whole current month and every summary comparison was wrong. It now comes from the month interval.
  Two test expectations were also wrong rather than the code (see below).

### Issues / deviations

* **The comparison windows clamp instead of rolling.** The source builds them with the JS `Date`
  constructor, which rolls day overflow *forward*: on 31 March an MTD-vs-MTD window ends on 3 March
  of the previous month, and the March after a leap day ends the YTD window on 1 March. Both are
  meaningless as comparison bounds, so the day is clamped to the target month's length instead —
  the same class of decision as Phase 8's month normalization. Tested for both cases.
* **`minDate` is parsed in the local calendar.** The source does `new Date('2024-01-15')`, which JS
  reads as UTC midnight, so in a negative-offset zone the earliest month shifted by a day. Parsing
  the column value in the calendar's zone (as the rest of the app already does) removes the quirk.
* **`summaryByGroup` / `yearlyGroup` are ported but have no catalog entry.** The source's
  `fetchReportData` and `handleReportDrillDown` both handle `yearlyGroup`, and
  `getReportYearlySummaryByGroup` exists — but no entry in the RN index reaches either, because
  there is no `app/reports/yearly-group.tsx`. Rather than invent a twelfth report, the SQL is ported
  and covered by the service tests, and the omission is recorded here.
* **A preserved source inconsistency:** the "Transactions By Group" overview lists **all-time**
  totals (it is `getReportGroupsOverview`), but its drill-down window is the **selected month** — the
  source only widens the window for the two overviews and the yearly reports. A group's total can
  therefore exceed the sum of the rows its drill-down shows. Tested so it stays deliberate.
* **The index is one config-driven page, not eleven screens.** The RN app has eleven near-identical
  screens differing only in their `ReportSelectors` props and one summary/data switch; those flags
  live on `ReportDestination` and drive a single `ReportDetailView`. The two genuine special cases
  (the group accordion, the living-cost config sheet) are handled inside it.
* **The period picker disables out-of-range months.** The RN `YearMonthSelector` lets you pick a
  month with no data; the stepper's bounds are applied to the month grid as well, which is the same
  rule the budgets phase's picker uses.
* **Report row glyphs are SF Symbols, not the stored Material icon names.** The same decision as
  `TransactionRow`: `category_app_icon` mapping belongs with Phase 12's category icon picker.
* **The `payees`/`categories` search field lives in a row above the list**, mirroring the RN
  `searchContainer` layout, rather than as a `.searchable` modifier (which cannot be applied
  conditionally without a wrapper). The sort picker is a toolbar menu; the sort caption sits under
  the field as in the source.
* **Two test expectations were wrong, not the code:** a 100% rise in *spending* is bad (red), so
  `isPositive` is false even though the percent is suppressed when there is no previous amount; and
  the group drill-down window is the month, as the preserved-inconsistency test above now documents.

---

## Phase 11 — Calendar

**Status:** COMPLETE (2026-09-21)

### What was done

* `Services/CalendarService.swift` — ports `calendarService.ts` plus the period logic the screen in
  `app/calendar-view.tsx` keeps inline:
  * **pure**: `daysInMonth` (the `eachDayOfInterval` grid), `leadingSlots`, `dayNetTotal`,
    `dateForPeriod` (`getNewDateForPeriod`), `steppedMonth`, `canStepBack`/`canStepForward`,
    `isSameDay`, `dayHeading`, `netText`, and the month-bound helpers;
  * **queries**: `transactions(userId:date:)` (`getTransactionsByDate`, delegating to the
    dashboard's identical SQL) and `minDate` (the earliest month the grid may page back to).
* `Support/TransactionBounds.swift` — **new**: the `MIN(date)` bound is now needed by budgets,
  reports *and* the calendar, so the query has one implementation. `BudgetService.minTransactionDate`
  and `ReportDetailViewModel.loadBounds` delegate to it (the same extraction pattern as Phase 9's
  `InitialSyncGuard`), and the calendar no longer reaches into `BudgetService` for a generic query.
* `Support/MonthYearPicker.swift` — **new**: the month/year popover was about to be written a third
  time (budgets, reports, calendar), so it is now one value-driven component (years in, a
  month-selectable predicate, an `onSelect`). `BudgetMonthPicker` and `ReportPeriodPicker` are
  deleted and all three screens use the shared picker.
* `Features/Calendar/` — `CalendarViewModel`, `CalendarMonthGrid`, `CalendarDaySummaryBar`, and the
  rewritten `CalendarView`. The Phase 4 placeholder is gone.
* Tests, 48 new (344 total): `CalendarCalculationTests` (the grid build, Sunday-first leading blanks,
  the day net and the sign convention, the period day rule, the month-step clamp, both navigation
  bounds, and the view model's navigation/derived state), `CalendarServiceTests` (the day list's
  scoping/ordering/empty state, the day boundary, the earliest-transaction bound and its fallbacks),
  `CalendarViewRenderingTests` (the screen in both collapse states, the grid across three month
  shapes, the summary bar's three states, the extracted picker in both shapes, and the derived
  values the screen reads).

### Verification

* `xcodebuild … clean build` → `BUILD SUCCEEDED`, no warnings.
* `xcodebuild … test -destination 'platform=macOS'` → `TEST SUCCEEDED` (344 tests, 0 failures).
  The green suite still includes Phases 5–10, so the two extractions and the budgets/reports picker
  swap did not regress them.
* Launch smoke test: the built app ran for 6 s and quit cleanly.

### Issues / deviations

* **The RN grid has no per-day amounts.** The Phase 11 brief in this file implied each cell would
  show that day's net; it does not — `CalendarGrid.tsx` renders day numbers only, and the selected
  day's total lives in `CalendarDaySummary`. The brief was wrong and no per-day amount was added: it
  would have been an unrequested divergence, not parity. The cell's net is now only in the day bar.
* **The grid is Sunday-first.** `CalendarGrid` pads with `days[0].getDay()` and labels the columns
  Sun…Sat — date-fns' default. That is deliberately *not* the Monday-first week
  `TransactionService.DatePreset.thisWeek` forces (`weekStartsOn: 1`); both are preserved as they
  are, and the test names which is which so a future agent does not "fix" one to match the other.
* **An explicit period change uses a different day rule than a step.** `getNewDateForPeriod` takes a
  day that does not fit the new month to the **1st** (`newDay = currentDay > daysInNewMonth ? 1 :
  currentDay`), while date-fns `subMonths` *clamps* onto the last day. The source uses each where it
  appears, so a stepper arrow clamps and a month-grid pick jumps to the 1st. Both are tested.
* `currentMonth` is normalized to the first of the month (as Phase 8 did for budgets), which removes
  a class of off-by-a-day questions without changing anything displayed — the source only ever uses
  month boundaries.
* **Today gets a thin outline when it is not the selected day.** The only macOS addition in this
  phase: on the source the two coincide at launch, so the distinction is invisible until you
  navigate away, where a pointer benefits from knowing where "today" is.
* **The collapse toggle and "Goto Today" move to the toolbar** (the matrix's macOS column calls for
  exactly that), and the pane split is calendar-left / day-right instead of stacked. "Goto Today"
  keeps the source's rule of appearing only when a non-today date is selected.
* **The two shared extractions are a deliberate scope expansion** for a calendar phase. Rationale:
  the picker was a third copy-paste of ~100 lines, and `MIN(date)` had already leaked from budgets
  into reports. Both are mechanical moves with the full suite re-run; the extracted picker also got
  its own render test, which the two originals never had.

## Phase 12 — Categories / Payees / Groups / Quick Transactions

**Status:** COMPLETE

### What was done

* `Support/CategoryIcon.swift` — the single Material→SF Symbol table (116 entries) plus the
  source's `formatIconName` normalisation (`Md` prefix strip, camelCase → kebab-case) and its
  per-context empty defaults. This is now what `TransactionRow`, `ReportItemRow`,
  `LivingCostConfigView`, the category rows and the editor's icon picker all use; no second table.
* `Support/EntityOrdering.swift` — the shared search + `name`/`priority` sort for the four screens,
  with JS `Array.prototype.sort` stability restored, reorder mode forcing ascending priority, and
  the move/renumber helpers the drag gesture and the arrows both use.
* `Support/ViewModePreference.swift` — per-screen list/grid (and card/list) persistence in
  `UserDefaults`, under the source's own keys and with its literals (`grid`/`list`, `Card`/`List`).
* `Services/CategoryService.swift`, `PayeeService.swift`, `GroupService.swift`,
  `QuickTransactionService.swift` — the list/filter/sort layer, the `MAX(priority)+1`
  auto-assignment, the upsert writes, `updatePriorities`, and each table's own delete shape
  (group hard delete, template soft delete, categories/payees none).
* `TransactionService.prefill` — the quick-transaction → transaction prefill, with the source's
  rules and quirks (no product link, no group, no default category, date = now, ids dropped when the
  referenced row is gone).
* `Features/Categories/` — `CategoriesView` (Expense/Income tabs, search, sort menu, drag reorder,
  list/grid), `CategoryRow`, `CategoryEditorView`, `CategoryIconPicker`.
* `Features/Payees/` — `PayeesView`, `PayeeRow`, `PayeeEditorView`.
* `Features/Groups/` — `GroupsView`, `GroupRow`, `GroupEditorView` (add/edit/delete with a member
  count warning).
* `Features/QuickTransactions/` — `QuickTransactionsView`, `QuickTransactionRow` (card + list),
  `QuickTransactionEditorView`, and the real `QuickTransactionPickerSheet`.
* Wiring: `AppState.openTransactions(filters:)` + `transactionFilterRequestID`
  (`initialSelectedCats` / `initialSelectedPayees`), `AppState.logQuickTransaction(_:)` + the
  picker's `onDismiss` hand-off, `AppState.transactionEditor = .template(_)`,
  `TransactionEditorTarget.template` / `TransactionEditorViewModel(template:)`, and a bolt toolbar
  button on `TransactionsView` (the RN screen's bolt FAB).
* Tests: `MetaEntityCalculationTests` (44), `MetaEntityServiceTests` (41),
  `ManagementViewsRenderingTests` (17) — 102 new, 421 total.

### Verification

* `xcodebuild … clean build` → BUILD SUCCEEDED, zero warnings.
* `xcodebuild … test -destination 'platform=macOS'` → TEST SUCCEEDED, 421 tests / 0 failures.
* Launch smoke test: the built app ran for 6 s and quit cleanly.
* RN project untouched; no debug leftovers.

### Issues / deviations

* **Three real bugs were caught by the new tests before the commit:** the category editor's icon
  preview used `symbolName(for:)` instead of `categorySymbol(_:)`, so an empty icon field previewed
  the fallback glyph instead of the source's `'category'` default; the `ViewModePreference` keys
  were derived from the case names (`@categories_view_mode_`) instead of the source's singular ones
  (`@category_view_mode_`); and `QuickTransactionService` stored an empty description as `''` where
  the source's `description || null` stores `NULL`. All three are fixed and asserted.
* **`Category` is ambiguous in the test target** (`XCTest`/Foundation ship a `Category` type), so the
  tests qualify it as `Jmoney.Category` — the convention the Phase 7 tests already established.
* **Categories and payees ship add-only.** The RN screens have no edit/delete and neither table has
  a `deleted` column, so a local delete (or rename) could not be represented to the sync layer and
  would be undone by the next full-replace pull. This follows the recorded rule in
  `DATA_ARCHITECTURE.md` §4 rather than inventing a destructive path; the editors say so in a footer
  so the limitation is visible rather than surprising.
* **The living-cost toggle stays where the source puts it** — the Living Costs report's config sheet
  (`LivingCostConfigView`, Phase 10), not the category editor. The Phase 12 brief and the earlier
  matrix row suggested a category-editor toggle; the source has no such control, so none was added.
* **Reorder renumbers the visible set only**, exactly as `moveItem` does, so the Expense and Income
  tabs can hold colliding priority values. Preserved and tested: the two lists are never displayed
  together, and the `priority ASC, name ASC` order each list relies on is unaffected.
* **Reorder mode is kept even though drag-and-drop mostly replaces it.** It still changes the order
  (fixed ascending priority), forces the list layout, and is where the source pushes the reordered
  priorities — the hook Phase 14's sync engine will use. The source's up/down arrows live in the row
  context menu beside the native drag gesture.
* **Group delete gains a warning the source does not have.** The alert names how many transactions
  keep their dangling `group_id`. The delete itself is unchanged (row removed, members untouched);
  this is a macOS addition because an invisible destructive consequence reads as a bug.
* **The quick-transaction picker chains two sheets through `AppState`.** Selecting a template closes
  the picker and reopens the editor from `onDismiss`; presenting the second sheet from inside the
  first is unreliable on macOS. The observable flow matches the source's route push.
* **No sort menu on Quick Transactions** — the source has none, so the order is always
  `priority ASC`.

---

## Phase 12 Verification Pass (third agent, 2026-09-21)

A third agent, prompted with the Phase 1 first-task instructions, found the project already at
Phase 12 with the entire implementation **uncommitted** in the working tree. Following the
second agent's precedent, the session became a verification pass over the uncommitted Phase 12
code, against the actual RN source rather than the docs:

* Read in full: all four RN entity services (`categoryService`, `payeeService`, `groupService`,
  `quickTransactionService.ts`), all four query modules (`metaQueries`, `groupQueries`,
  `quickTransactionQueries`, plus `add-quick-transaction.tsx`, `categories.tsx`, and the
  `quickTx` prefill branch in `add-transaction.tsx`.
* Read in full on the macOS side: `EntityOrdering.swift`, `ViewModePreference.swift`,
  `CategoryIcon.swift`, all four new services, `TransactionService.prefill`, and the
  quick-transaction editor view model's default-category handling.
* **Verdict: the Phase 12 implementation matches the source.** Search gate vs needle trimming,
  groups' description search, quick transactions' trimmed needle + name-only search + priority-only
  order, visible-set renumbering, the `MAX(priority)+1` shapes (including quick transactions'
  filtering `deleted = 0`), the `|| null` idiom and zero-amount rule, the identifier rules, the
  `'category'` icon default vs the payees' deliberate no-default, group hard delete, template soft
  delete, and every prefill quirk were all confirmed line-by-line. No code changes were required.
* Two documentation points noted: the template editor's type-switch default category (general/salary)
  was implemented in Phase 12 but not called out in the progress log (now recorded above), and
  the RN behavior it matches was re-confirmed in `add-quick-transaction.tsx`.
* **RN project confirmed untouched** (`git status` clean in `jayledger`). `.freebuff` added to
  `.gitignore` as part of the session's housekeeping; no tooling directories are committed.

The uncommitted work was then finalized as the Phase 12 commit: `BUILD SUCCEEDED` (Debug,
no warnings) and `TEST SUCCEEDED` (421 tests, 0 failures) immediately before committing.

## Phase 13 — Settings

**Status:** COMPLETE (2026-09-22) — commit `a8f1ef2`

### What was done

* `Support/AppearancePreference.swift` + `Stores/AppearanceStore.swift` — the `app_theme` port.
  Three choices (System/Light/Dark) driving `.preferredColorScheme` at the scene root; `System` is
  stored as an **absent key**, which is exactly the source's "follow the system" state. The store is
  shared by both scenes so the sidebar and ⌘, cannot disagree.
* `Support/ReminderPreference.swift` — the `notification_pref` port: the four named choices plus a
  custom `HH:mm`, the row display strings (`Off`, `Morning (9:00 AM)`, `Custom (6:30 PM)`), the
  selection rule (`isCustomChoice` = "contains a colon"), and the trigger times. `None` **removes**
  the key, as the source's `removeItem` does.
* `Services/NotificationService.swift` — `UserNotifications` scheduling of the daily reminder, in the
  source's order (permission → cancel → clear or schedule) with its copy preserved
  (`Reminder 💰` / "Don't forget to add your expenses for today!").
* `Support/BiometricPreference.swift` + `Services/BiometricService.swift` — the `use_biometrics` key
  (the source's `"true"`/`"false"` **strings**) plus `BiometricGate`, the pure decision table for the
  enable/disable flow. `BiometricService` is the thin `LAContext` wrapper that maps
  `canEvaluatePolicy`/`biometryType` onto the source's `hasHardware` + `isEnrolled` pair.
* `Services/SettingsService.swift` — `resetAppData` (the six-table wipe, and deliberately **not**
  `quick_transactions`) and the exact 12-key preference teardown.
* `Support/SyncPreference.swift` — reads/writes `@last_sync_master_<userId>`, so the settings row and
  the status bar report a real timestamp instead of a placeholder.
* `Features/Settings/` — `SettingsView` (the real form, hosted by *both* `SettingsPaneView` and
  `SettingsSceneView`), `SettingsViewModel`, `ReminderChooserSheet`, and the shared `SettingsRow` /
  `SettingsRowLabel`. The Phase 4 placeholders are gone.
* Wiring: `AppearanceStore` injected into both scenes (and, after a build-time crash, the main
  `WindowGroup` too); `AppState.refreshLastSync(userId:)`; the appearance override applied in
  `RootView`.
* Tests, 62 new (483 total): `SettingsPreferenceTests` (31 — appearance storage/fallback, reminder
  parse/save/display/format/selection/schedule rules, the biometric gate table, the sync key), plus
  `SettingsServiceTests` (8 — wipe scope, the template survival, per-user scoping, the exact key
  list and its survivors, transactional rollback) and `SettingsViewModelTests` (14 — the toggle flows
  and the reset path with the capability calls injected) and `SettingsViewRenderingTests` (9).

### Verification

* `xcodebuild … clean build` → `BUILD SUCCEEDED`, zero warnings.
* `xcodebuild … test -destination 'platform=macOS'` → `TEST SUCCEEDED` (483 tests, 0 failures).
  The green suite still includes Phases 5–12, so the `AppState`/`RootView` wiring did not regress them.
* Launch smoke test: the built app ran for 6 s and quit cleanly.
* Three real bugs were caught before commit and are worth knowing about:
  1. `SettingsService.resetLocalData` originally opened its own `db.inTransaction`, which GRDB
     rejects inside `DatabasePool.write` ("cannot start a transaction within a transaction"). It
     would have failed the reset in the app, not just in tests. The caller's write is now the
     transaction, which is what the source's explicit `BEGIN`/`COMMIT` amounts to.
  2. The reminder preference was persisted inside `NotificationService`, which made the flow
     untestable and was the wrong layer besides — the source's `handleNotificationChange` hook is
     what writes `notification_pref`. Persistence moved to `SettingsViewModel.selectReminder`.
  3. `AppearanceStore` was injected into the Settings scene but not the main `WindowGroup`, so
     `RootView` crashed on launch with "No Observable object of type AppearanceStore found".

### Analysis re-verification (third pass, 2026-09-22)

This session began with the master prompt's first-agent instructions ("analyze the source, produce
the three docs"), but the project was already at Phase 12 → 13 with Phases 1–3 complete and twice
verified. Per the master prompt §20 ("continue from the current state rather than starting over") and
§22 (whose first-task rules are explicitly conditional on being the *first* agent), the analysis was
re-verified rather than rewritten, and Phase 13 was implemented.

Re-read from source: `app/(tabs)/settings/index.tsx`, `src/hooks/useAppSettings.ts`,
`src/hooks/useBiometrics.ts`, `src/services/notificationService.ts`, `resetAppData` in
`src/db/queries.ts`, `ThemeContext.tsx`, `AuthContext.tsx`, plus spot-checks of every
`CREATE TABLE`/`ALTER TABLE`/`CREATE INDEX` in `src/db/database.ts` and the sync claims in §3.2–§3.4.

**Verdict: the analysis is accurate.** The reset key list, the six-table wipe and its omission of
`quick_transactions`, the `is_living_cost` push strip, the budget `Monthly`→`Month` normalization,
both last-sync key spellings, the quick-transactions born-dirty `DEFAULT 1`, and all 11 indexes with
their composite column order match the code exactly. No corrections to the matrix or the architecture
were required.

**One wording correction**, in this file's own Phase 13 brief (now superseded): it described the theme
as storing `light`/`dark`/`system`. The source only ever **stores** `"light"` or `"dark"`; `system` is
the behavior of an **absent** key. `MACOS_FEATURE_MATRIX.md` §10 already stated this correctly, and
`DATA_ARCHITECTURE.md` §8 now records the correction.

### Issues / deviations

* **Three-way appearance picker.** The source's screen offers only Light and Dark, so a user can never
  return to following the system even though that is the initial state. macOS exposes `System` as an
  explicit choice mapped onto the absent key. Stored data and the default are unchanged.
* **A refused notification permission is reported.** The source stores the preference, then logs and
  swallows the refusal, leaving the row claiming a reminder that will never fire. The choice is still
  stored here (parity), but the refusal now surfaces in the status bar.
* **Reset also cancels the pending OS reminder.** The source clears `notification_pref` without
  cancelling the scheduled notification, so a reset app would keep notifying while the row reads
  "Off". This is the phase's one deliberate addition to the reset path.
* **Reset is not transactional on its own.** `resetLocalData` relies on the caller's
  `DatabasePool.write`; calling it outside a write transaction would leave the wipe non-atomic.
  Documented on the method.
* **The reset confirmation states the quirk** instead of hiding it: the source is silent about
  templates surviving, and the master prompt forbids silently omitting functionality. Flagged here as
  a decision item: if the user wants Reset Data to also clear templates, that is a one-line change to
  `SettingsService.tablesClearedByReset` **and** a deliberate divergence from the source.
* **The biometric message is the source's single sentence** for both failure modes ("does not support
  biometrics or no fingerprints/faces enrolled"). `BiometricGate.Availability` still distinguishes
  `noHardware` from `notEnrolled`, so the copy can be split later without touching the rules.
* **The haptics row is shown disabled, not removed**, with the reason in its subtitle. The matrix
  records this as MACOS EQUIVALENT.
* **⌘R / Cloud Sync still reports "Sync isn't connected yet."** The row now shows the real
  `@last_sync_master_` value ("Never synced" until Phase 14 writes one); the engine itself is
  Phase 14's.
* **The settings window and the sidebar pane share one form** rather than the source's single tab.
  A Mac app conventionally has a ⌘, window, so both exist and render the same view.
* **`app_theme` and `use_biometrics` survive a reset**, because the source's key sweep does not name
  them. Preserved and asserted in tests; `AppearanceStore` is re-read after a reset for that reason.

## Phase 14 — Authentication / Sync

**Status:** COMPLETE (2026-09-22)

### What was done (by the agent that started this session's work, found uncommitted)

The phase was implemented in a prior session and left uncommitted in the working tree. This session
verified it against the RN source, completed the remaining items, and committed everything.

**Found in the tree (verified, not rewritten):**

* `Support/SupabaseConfig.swift` + `Jmoney.xcconfig` — credentials resolve from build configuration
  (xcconfig → Info.plist → runtime), never source (§15). The committed xcconfig is an **empty
  template** (with the `https:/$()/host` escaping note); an unconfigured build is a supported state:
  `CloudServices` swaps in honest stubs, the gate says sign-in is unavailable, and sync attempts
  report the configuration reason instead of pretending.
* `Support/KeychainStore.swift` + the Keychain session storage — real sessions, `autoRefreshToken`,
  `emitLocalSessionAsInitialSession` for the local-first restore.
* `Stores/SessionStore.swift` — replaced the mock, public surface unchanged; ports the 7-second
  restore timeout (a task-group race) and keeps sign-out data-preserving.
* `Services/Auth/` (`AuthProviding` + `SupabaseAuthService`), `Services/CloudServices.swift`,
  `Services/ConnectivityMonitor.swift` (NWPathMonitor behind `ConnectivityProviding`),
  `Support/JSONValue.swift`.
* `Services/SyncService.swift` + `Services/Sync/` — the full engine: `runFullSync` (push-all,
  seven ordered pulls, the source's progress strings, the `isSyncing` guard, master timestamp only
  on success), `syncTransactions(isPartial:)` with the push-before-wipe force resync,
  `needsTransactionSync`, and one module per entity. Every documented quirk preserved and tested.
* `Support/SyncPolicy.swift` — the screens' sync predicates as pure functions.
* Wiring: `RootView` is the sync runner (`syncRequestID`/`transactionSyncRequest`/
  `entitySyncRequest`), the dashboard runs the focus check (`needsTransactionSync` + the auto-sync
  gate; the documented `isPartial` deviation noted on the method), the transactions toolbar sync
  button, Settings' Sync Now row, and the transaction row's "not yet uploaded" cloud badge.
* Tests: `SyncFoundationTests` (20) and `SyncEngineTests` (43) — the protocol quirks asserted
  end-to-end against a fake backend.

### What this session verified and added

* **Verification pass (fourth)** — re-read `syncService.ts`, all seven sync modules, `baseSync.ts`,
  `AuthContext.tsx`, `useBiometrics.ts`, `BiometricLock.tsx`, `_layout.tsx`'s lock lifecycle, and
  the sync call sites of every screen. **Verdict: the engine, auth and quirks match the source**;
  findings folded into `DATA_ARCHITECTURE.md` §8 (the `performGroupSync` service-key stamp, the six
  manual sync buttons, the timestamp-only guards, the reorder-exit pushes, the post-write syncs,
  the lock's password-fallback prompt).
* **App-lock overlay** (`Features/Auth/AppLockView.swift`) — `RootView` covers the whole window
  when `AppState.isLocked`, set at launch and on every `didBecomeActive` when
  `BiometricPreference.isEnabled` (the `'true'`-string test). Auto-prompts on mount; the error box
  and "Unlock App" retry mirror `BiometricLock.tsx`. The lock prompt is `.deviceOwnerAuthentication`
  (the source passes `disableDeviceFallback: false`), while the Settings enable flow stays
  biometrics-only — the two different calls preserved.
* **Manual sync buttons on all six management screens** — `Support/ManagementSyncButton.swift`
  (spinner while syncing, the RN headers' refresh behaviour); per-entity success strings in the
  status bar match the RN toasts ("Budgets synced successfully.").
* **First-open guards wired**: budgets/goals call their `shouldRunInitialSync` predicates
  (`@initial_*_sync_checked_` written after completion, as `handleBudgetSync`/`handleGoalSync` do);
  categories/payees/groups/quick-transactions use the timestamp-only
  `SyncPolicy.needsTimestampOnlySync`. Groups re-fires every open — the source's key-mismatch
  quirk — and converges only because the port re-stamps the groupService key after a groups sync
  (`SyncPreference.groupServiceLastSyncKey`), exactly as `performGroupSync` does.
* **Reorder-exit pushes**: exiting reorder mode on categories/payees/groups/quick-transactions
  fires `AppState.requestEntityPush` → `SyncService.pushEntity` (push-only, no pull, no flags;
  the per-entity key re-stamped by the runner) — the `backgroundPush…` functions.
* **Post-write syncs**: goals/budgets editors and delete confirmations request their entity sync;
  transaction save/delete requests a partial transaction sync — the RN handlers' fire-and-forget
  calls.
* Tests, 15 new (574 total): `Phase14CompletionTests` — the push-only path (dirty-only push,
  clean marking, no pull/no stamp, offline short-circuit, failure leaves rows dirty, the
  re-entrancy guard via a re-entrant backend), the timestamp-only guard, the lock flag and the
  `'true'`-string preference test, the sync button's syncing state and labels, and the request
  plumbing (key carrying, counter bumping, nil-user rejection).
* `xcodegen generate` (two new files); `project.yml` unchanged since the prior session's Supabase
  package addition.

### Verification

* `xcodebuild … build` → `BUILD SUCCEEDED`, no compile warnings.
* `xcodebuild … test -destination 'platform=macOS'` → `TEST SUCCEEDED` (574 tests, 0 failures).
* Launch smoke test: the built app ran for 5 s and quit cleanly.

### Issues / deviations

* **The groups screen syncs on every open** (source parity): its guard reads `@last_sync_groups_`,
  which the pull never writes. The port preserves this and makes it converge the same way the
  source does — the post-sync stamp of the service key. Tested via the key-shape assertion.
* **The dashboard's automatic transaction sync is partial, not force** — the source's
  `syncTransactions(userId, manual)` argument swap would re-download the entire ledger on every
  dashboard focus; the deviation is documented on the call site and was already recorded in
  `DATA_ARCHITECTURE.md` §8.
* **The first-launch sync modal is not reproduced** — the RN `DashboardSyncModal` blocks the screen
  for a background concern; the macOS status bar carries the same progress strings.
* **The lock's window coverage is an overlay, not a route swap** — the RN app swaps the whole nav
  tree for `BiometricLock`; a Mac window keeps its hierarchy and covers it, which also means the
  unlock does not re-trigger the boot sequence.
* The lock auto-prompt cannot run in unit tests (real Touch ID); the state machine and the
  preference test are covered instead.

## Phase 15 — Import / Export

**Status:** COMPLETE (2026-09-23)

A **macOS-original feature** — the RN app has none (matrix §12), so there is no parity contract
here beyond the data itself.

### What was done

* `Support/CSV.swift` — a minimal RFC 4180 codec: quoting/doubling, CRLF+LF decode, BOM on encode
  and skipped on decode, embedded newlines preserved.
* `Services/ExportService.swift` — transactions CSV through `TransactionService.transactions` with
  the **screen's filter state** (so File > Export can export what is on screen), plus
  categories/payees/goals CSVs and a JSON **backup** of all seven tables for the user with
  `format`/`version`/`exported_at` metadata and the sync internals (`sync_status`, `tid`,
  `deleted`) verbatim — a backup is a true snapshot, soft-deleted rows included. Column headers
  are the schema's snake_case names.
* `Services/ImportService.swift` — a deliberately narrow **transaction CSV import**: header matched
  by column name with required-column validation before anything is written; category/payee/group
  matched **by name** (case-insensitive, trimmed) against the user's existing rows; missing matches
  **skip the row and are reported — nothing is created silently**; every row passes the existing
  `Validators` (amount bounds, description ≤ 500) plus type/date checks; blank `date` derives from
  the timestamp prefix; blank/sentinel ids (`null`, `undefined`) become fresh UUIDs (§7); blank
  optionals insert as SQL NULL; rows are **born dirty** (`sync_status = 1`) so the next sync
  uploads them; `tid = 0`. Validation runs over *all* rows before any insert, and the insert batch
  relies on the **caller's** `pool.write` transaction (the `SettingsService.resetLocalData`
  pattern — GRDB refuses nested transactions), so an exception mid-batch rolls everything back.
* `Features/Export/ExportSheetView.swift` — format picker (all six exports), `NSSavePanel`, dated
  file names, status-bar confirmation. `Features/Export/ImportSheetView.swift` — choose → preview
  (first 5 rows) → import → the **per-row report** listing every skip with its reason.
* `App/AppCommands.swift` — File > Export… (**⌘E**) and File > Import Transactions….
* `AppState` — `showExportSheet`/`showImportSheet`, and `transactionsFilters`: a live snapshot of
  the Transactions screen's filter state recorded on every reload (`TransactionsViewModel.appState`,
  weak), which is what makes "export what's on screen" possible without the shell owning filters.
* Tests, 25 new (599 total): the CSV codec (round-trip with quoted/embedded-newline fields, BOM,
  both row endings, minimal quoting), export rows/header/schema-name/sentinel assertions, the
  filtered export, the JSON backup shape (seven tables, metadata, NULL-vs-empty, deleted rows
  included), parse errors, born-dirty inserts, name mapping (case-insensitive) with the stored
  spelling, unknown category/payee/group skips that create nothing, every validator message
  (including the `1,234` non-truncation rule), sentinel-id replacement, the all-or-nothing batch,
  line-numbered reports, and the **export → import round trip** into a different database/user.

### Verification

* `xcodebuild … build` → `BUILD SUCCEEDED`, no compile warnings.
* `xcodebuild … test -destination 'platform=macOS'` → `TEST SUCCEEDED` (599 tests, 0 failures).
* Launch smoke test: the built app ran for 6 s and quit cleanly.
* The suite caught a real bug before commit: **Swift treats `\r\n` as a single `Character`
  (grapheme cluster)**, so the decoder's original `case "\r"` never matched a CRLF pair and whole
  spreadsheet rows merged into one field. Fixed as `case "\r", "\r\n"` and pinned by tests.

### Issues / deviations

* Import is transactions-only by design (the brief's "clearly-scoped" requirement). A full JSON
  *restore* is intentionally not implemented in this phase: restoring a snapshot must resolve id
  collisions and interact with the sync protocol (a naive restore would fight the next pull), and
  deserves its own design pass. The backup file is tool-readable and complete; the phase-16+ agent
  should treat "restore from backup" as an open item, not an oversight.
* Export writes the *stored* denormalized names (`category_name` etc.), not the entities' current
  names — faithful to the schema, which is what a CSV/backup should capture.
* The import's per-row report is shown in the sheet and summarized in the status bar; per-row
  error text uses the validators' exact source messages.
* Ids: a provided id is kept as-is (round-trip stability, idempotent re-import upserts in place),
  which also means re-importing an exported file updates rather than duplicates rows — consistent
  with the app's upsert-by-id write path.

## Phase 16 — macOS Commands / Keyboard Shortcuts

**Status:** COMPLETE (2026-09-23)

### The audit (what was found)

* **Already wired, conflict-free (kept):** ⌘N New Transaction, ⌘⇧N Quick Transaction (Phase 4);
  ⌘F Edit > Find… — safe because the app does not include `TextEditingCommands`, so there is no
  Find submenu to shadow; ⌘R Data > Sync Now; ⌘E Export… (Phase 15); ⌘, by the Settings scene.
  Per-view: ⌫ delete on the Transactions/Budgets/Goals selections, Return/double-click to edit,
  Escape/Return in every editor sheet, `.defaultAction`/`.cancelAction` in all sheets and panels.
* **Gap: no per-section New commands** — New Budget / New Goal / New Category / New Payee / New
  Group / New Template had no menu presence or key equivalents (deferred by Phases 8–12 to
  "Phase 16 owns the shortcut set").
* **Gap: Import had no key equivalent** (the Phase 15 addition was menu-only).
* **Gap: no Data-menu route to a section's own sync** — the six management screens' toolbar sync
  buttons were toolbar-only.
* **Verified non-conflicts:** the standard ⌘X/C/V/A/Z/O/P/S/Q/W/M slots are untouched; the app
  never uses option/control modifiers; ⌘M (minimize), ⇧⌘A/H and the ⇧⌘ digit shots are clear.

### What was done

* **`AppCommands.menuAuditTable`** — the shortcut set's single source of truth (title, key,
  modifiers per item). The menu body builds from the same declarations, and `CommandsTests` runs
  the standard-macOS conflict rules against the table, so a future shortcut addition that ignores
  the audit fails the suite. The three plain-⌘ re-uses (`n`, `e`, `f`) each carry their safety
  reason in the test and are pinned by it.
* **File > New *section* items** — New Budget… (⇧⌘B), New Goal… (⇧⌘G), New Category… (⇧⌘C), New
  Payee… (⇧⌘P), New Group… (⇧⌘T), New Template… (⇧⌘M). Each selects its sidebar section and raises
  `AppState.requestSectionEditor()`; the section's list view observes the counter and presents its
  editor **only when frontmost** (`selectedSection` guard), so the request is answered exactly once
  no matter how many section views are alive in the split view's lifetime. The ⇧⌘ letters were
  chosen against the system ⇧⌘ map (A/H/digits clear); none collide with each other or with ⌘⇧N.
* **File > Import Transactions… (⇧⌘I)** — closes the Phase 15 gap.
* **Data > Sync Transactions** and **Data > Sync This Section** — the toolbar buttons' menu twins;
  the latter rides the same request channel as the screens' own buttons.
* **`AppSection.syncEntity`** — the section→entity mapping for Sync This Section, as a tested
  property (every entity reachable exactly once; dashboard/calendar/reports/settings deliberately
  `nil` and fall back to ⌘R's full sync).
* Observers added to Transactions, Budgets, Goals, Categories, Payees, Groups and Quick
  Transactions; the request channels themselves are unit-tested.
* Tests, 9 new (608 total): the audit table's shape, per-modifier-set key uniqueness, the plain-⌘
  and ⇧⌘ conflict rules (with the documented re-uses), the modifier whitelist, the re-use pin,
  the sync-entity mapping (bijective onto the seven entities; `nil` for the four full-sync
  sections), and the request-channel counters.

### Verification

* `xcodebuild … build` → `BUILD SUCCEEDED`, no compile warnings.
* `xcodebuild … test -destination 'platform=macOS'` → `TEST SUCCEEDED` (608 tests, 0 failures).
* Launch smoke test: the built app ran for 6 s and quit cleanly.

### Issues / deviations

* **⌘E stays on Export** rather than the historic "Enter selection" binding: the audit treats
  menu-command parity as the stronger convention for a data app, and the selection-open role is
  already Return's. Documented here so the choice is deliberate.
* **No ⌘D (Bookmarks), ⇧⌘F (Recents), ⌘⌥-series, or F-key additions**: the audit adds nothing
  without a workflow reason; the set is complete for the app's flows, and more bindings would
  increase collision surface without user value.
* The section-editor requests are *present* requests, not focus requests: the editor sheet opens
  through the same `.sheet(item:)` the toolbar buttons use, so keyboard focus lands in the first
  field by the system's default sheet behavior rather than custom first-responder code.
* A first draft of the audit test tried to introspect SwiftUI's opaque `Commands` content and was
  discarded as dishonest; the audit table + conflict rules are the honest replacement.

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
| 2026-09-21 | Report comparison windows clamp instead of rolling (MTD/YTD)  | The JS `Date` constructor rolls day overflow forward (31 Mar → 3 Mar of the previous month), which is meaningless as a comparison bound; same class of fix as Phase 8's month normalization | Phase 10 |
| 2026-09-21 | `previousTotal` sums unfiltered rows while `totalAmount` sums filtered ones | Preserves the source's ordering; changing it would alter every banner trend | Phase 10 |
| 2026-09-21 | Reports are one config-driven page, with the per-report flags on `ReportDestination` | Eleven near-identical RN screens differ only in their selector props; one page plus a catalog is the macOS reading and keeps the flags testable | Phase 10 |
| 2026-09-21 | `reports_view_mode` persists to `UserDefaults`                    | A local UI preference, not user data, so it does not belong in the DB or in sync | Phase 10 |
| 2026-09-21 | Report search matches `name`/`category_name`/`payee_name` only     | Faithful to `sortReportData`'s search branch, which omits `group_name` even though its sort branch uses it | Phase 10 |
| 2026-09-21 | Toggling `is_living_cost` does not set `sync_status = 1`           | The column is stripped on push and omitted on pull, so flagging it dirty would cause a pointless push cycle | Phase 10 |
| 2026-09-21 | `summaryByGroup`/`yearlyGroup` SQL is ported without a catalog entry | The source handles them but no RN screen reaches them; porting the SQL keeps the service a complete mirror without inventing UI | Phase 10 |
| 2026-09-21 | The `MIN(date)` bound is shared (`TransactionBounds`)                  | A third consumer (the calendar) arrived, and reports had already reached into `BudgetService` for a generic query; same extraction pattern as `InitialSyncGuard` | Phase 11 |
| 2026-09-21 | One `MonthYearPicker` replaces the budgets and reports copies          | The month/year popover was written twice and about to be written a third time; the shared component is value-driven so each screen keeps its own selection semantics | Phase 11 |
| 2026-09-21 | The calendar grid stays Sunday-first, the quick ranges stay Monday-first | `CalendarGrid` uses date-fns' default week start while `DatePreset.thisWeek` forces `weekStartsOn: 1`; both are the source's, so both are preserved and named in tests | Phase 11 |
| 2026-09-21 | The calendar grid shows day numbers only, no per-day amounts         | Faithful to `CalendarGrid.tsx`; the selected day's total is in the day summary. Adding per-day nets would be a divergence, and the Phase 11 brief that implied otherwise was wrong | Phase 11 |
| 2026-09-21 | A period pick jumps a too-long day to the 1st; a step clamps to the month end | `getNewDateForPeriod` and date-fns `subMonths` genuinely differ in the source, so each is used where it appears | Phase 11 |
| 2026-09-21 | One Material→SF Symbol table (`CategoryIcon`) backs every category glyph | `app_icon` is a Material name stored in the DB and free-text typed in the source; macOS has no Material font, so exactly one translation table exists and all renderers share it | Phase 12 |
| 2026-09-21 | The icon table is curated, with a neutral fallback for unknown names | The source accepts any string, so an exhaustive table is impossible; drawing nothing for an unmapped name would read as a bug | Phase 12 |
| 2026-09-21 | Category and payee screens stay add-only | The source offers no edit/delete for them and neither table has a `deleted` column, so a local delete or rename could not be pushed and would be resurrected by the next full-replace pull (DATA_ARCHITECTURE.md §4) | Phase 12 |
| 2026-09-21 | Shared `EntityOrdering` for search + name/priority sort | The three `filterAndSort*` services were identical but for their search field; one implementation keeps the four screens from drifting | Phase 12 |
| 2026-09-21 | Reorder renumbers the visible set, as `moveItem` does | Faithful to the source, including the consequence that the Expense and Income tabs renumber independently and can collide | Phase 12 |
| 2026-09-21 | Drag-and-drop reorder, with the source's arrows in the context menu | `onMove` is the native Mac gesture; the arrows are what the source offers and stay keyboard-reachable | Phase 12 |
| 2026-09-21 | Reorder *mode* is kept alongside drag-and-drop | It changes the order (fixed ascending priority), forces the list layout, and is where the source pushes — the hook Phase 14 will use | Phase 12 |
| 2026-09-21 | View modes persist in `UserDefaults` under the source's keys | The RN app uses AsyncStorage; keeping the key names and values makes the preference semantics identical, only the store differs | Phase 12 |
| 2026-09-21 | Group delete warns how many transactions keep their reference | The source's delete is silent about the dangling `group_id`; the delete is unchanged, but the consequence is now visible | Phase 12 |
| 2026-09-21 | The quick-transaction picker hands its selection over via `AppState` | Presenting the transaction editor from inside the picker sheet is unreliable; the selection rides the picker's `onDismiss`, so the flow stays one click | Phase 12 |
| 2026-09-21 | A template's `product_link` is not prefilled into a transaction | Faithful to `add-transaction.tsx`, which applies only type/amount/description/category/payee from a `quickTransaction` param | Phase 12 |
| 2026-09-22 | Appearance offers System/Light/Dark, with `System` stored as an **absent** key | The source only stores `light`/`dark` and treats a missing key as "follow the system", but its screen offers no way back to it. Absent-key storage keeps the data and default identical while making the fallback reachable | Phase 13 |
| 2026-09-22 | `app_theme` (not a new key) carries the appearance override; `AppearanceStore` sits above both scenes | Reuses the source's key; a root-level store is what lets `.preferredColorScheme` cover the main window *and* the ⌘, window | Phase 13 |
| 2026-09-22 | One `SettingsView` hosts both the sidebar pane and the ⌘, scene | A Mac app conventionally has a settings window while the source has a tab; rendering one view in both places stops them drifting apart | Phase 13 |
| 2026-09-22 | `use_biometrics` keeps the source's `"true"`/`"false"` **string** values | `useBiometrics.ts` compares against the literal `'true'`; storing a boolean would silently change the read rule | Phase 13 |
| 2026-09-22 | The biometric gate is a pure decision table (`BiometricGate`) with a thin `LAContext` wrapper | The source's order (hardware → enrolment → authenticate → only then persist) is the behavior worth testing, and it cannot be tested against real Touch ID hardware | Phase 13 |
| 2026-09-22 | Biometrics-only policy (`.deviceOwnerAuthenticationWithBiometrics`) | Matches `expo-local-authentication`'s `authenticateAsync`, which never offers the account password as a fallback | Phase 13 |
| 2026-09-22 | Capability calls are injected into `SettingsViewModel` | Makes the whole toggle flow — including which paths persist and which stay silent — unit-testable without Touch ID or a notification centre | Phase 13 |
| 2026-09-22 | The reminder preference is written by the view model, not by `NotificationService` | `handleNotificationChange` is what writes `notification_pref` in the source; keeping the write in the service made the flow untestable and the layering wrong | Phase 13 |
| 2026-09-22 | A refused notification permission still records the choice, but is reported in the status bar | The source stores the preference then only logs the refusal, so its row claims a reminder that will never arrive. Parity of the stored data, plus an honest UI | Phase 13 |
| 2026-09-22 | `SettingsService.resetLocalData` relies on the caller's write transaction | GRDB refuses to nest `inTransaction` inside `DatabasePool.write`; the caller's write is the equivalent of the source's explicit `BEGIN`/`COMMIT` and keeps the wipe atomic | Phase 13 |
| 2026-09-22 | Reset additionally cancels the pending OS reminder | The source clears `notification_pref` without cancelling the scheduled notification, leaving an app that reads "Off" while still notifying. The phase's one deliberate addition to the reset path | Phase 13 |
| 2026-09-22 | The reset confirmation states that templates survive | The source is silent about the `quick_transactions` omission; the master prompt forbids hiding functionality, so the consequence is made visible rather than "fixed" silently | Phase 13 |
| 2026-09-22 | The haptics row is disabled with an explanation rather than removed | Records the MACOS EQUIVALENT decision in the UI itself, instead of leaving users to wonder where the setting went | Phase 13 |
| 2026-09-22 | Credentials via `Jmoney.xcconfig` (committed as an empty template) → Info.plist → `SupabaseConfig` | Master prompt §15 forbids secrets in source; an unconfigured build stays buildable and runs local-only with honest stubs | Phase 14 |
| 2026-09-22 | An unconfigured build is a supported state, not an error | The app must build and run in a fresh checkout; cloud features explain why they are unavailable rather than failing cryptically | Phase 14 |
| 2026-09-22 | `SessionStore` keeps its public surface; only the internals swap to supabase-swift + Keychain | The shell, every per-user query, the status bar and Settings read it; the mock-to-real swap must be invisible to them | Phase 14 |
| 2026-09-22 | `emitLocalSessionAsInitialSession` on the Supabase client | The source's `getSession()` is local-first; the 7-second restore guard should not be spent on a refresh round-trip | Phase 14 |
| 2026-09-22 | Sync requests ride `AppState` counters; `RootView` owns the runner | Any view or command can request a sync without holding services; one place serializes the outcomes into the status bar | Phase 14 |
| 2026-09-22 | The dashboard's automatic transaction sync is partial, not force | The source's `manual` argument lands in the `isPartial` slot, making its auto-path a full wipe-and-redownload; almost certainly a bug, documented as a deviation | Phase 14 |
| 2026-09-22 | The first-launch sync modal becomes status-bar progress | A modal would block the window for a background concern; the RN progress strings are preserved verbatim | Phase 14 |
| 2026-09-22 | The lock overlay covers the window; the nav hierarchy stays | A Mac window keeps its state across a lock; the RN route swap would restart the boot sequence on unlock | Phase 14 |
| 2026-09-22 | The lock allows the OS password fallback; enabling stays biometrics-only | The source passes `disableDeviceFallback: false` for the lock but uses the biometrics-only policy for the enable prompt — two different calls, both preserved | Phase 14 |
| 2026-09-22 | A groups sync writes both group keys (pull's `-transaction_groups_`, service's `-groups_`) | Preserves the source's key-mismatch quirk *and* its convergence via `performGroupSync`'s extra stamp, without renaming the load-bearing sync-module key | Phase 14 |
| 2026-09-22 | The reorder-exit push is push-only; the caller re-stamps the last-sync key | The JS `backgroundPush…` functions are fire-and-forget and stamp from the call site; the engine's `pushEntity` must not grow pull/flag side effects | Phase 14 |
| 2026-09-23 | Export headers use the schema's snake_case column names | The CSV is a data snapshot, not a report; schema names keep it faithful to what sync exchanges and make the file self-describing for re-import | Phase 15 |
| 2026-09-23 | Import matches category/payee/group by **name**, creates nothing silently | The brief's core safety rule: an unknown name skips its row and is reported instead of inventing entities that would then sync to the server | Phase 15 |
| 2026-09-23 | Imported rows are born dirty and keep provided ids | `sync_status = 1` gets the rows uploaded by the next sync; idempotent re-import (upsert-by-id) matches the app's write path and makes export→import a round trip | Phase 15 |
| 2026-09-23 | Import batch atomicity rides the caller's `pool.write` | Same constraint as `SettingsService.resetLocalData`: GRDB refuses nested `inTransaction` inside `DatabasePool.write`; one transaction = all valid rows or none | Phase 15 |
| 2026-09-23 | The JSON backup stores raw column values incl. sync internals, NSNull for NULL | A backup must be a true snapshot (restore-worthy), not a cleaned view; NULL-vs-empty-string distinction survives round trips through the file | Phase 15 |
| 2026-09-23 | A JSON *restore* is not implemented in Phase 15 | Restoring must resolve id collisions and cooperate with the sync protocol (a naive restore fights the next pull); recorded as an open item instead of shipping a half-design | Phase 15 |
| 2026-09-23 | `menuAuditTable` as the shortcut set's single source of truth | SwiftUI `Commands` content is opaque, so the audit pins the contract as data and runs the HIG conflict rules against it in tests; adding a shortcut without clearing the audit fails the suite | Phase 16 |
| 2026-09-23 | Section editors answer requests only when frontmost | Multiple section views stay alive in the split view's lifetime; a `selectedSection` guard on each observer makes the menu's request land on exactly one view | Phase 16 |
| 2026-09-23 | ⇧⌘B/G/C/P/T/M for the per-section New items | The item initials, checked against the system ⇧⌘ map (A/H/digits) and each other; ⇧⌘ keeps them clear of the app's plain-⌘ set | Phase 16 |
| 2026-09-23 | ⌘E stays Export rather than a selection-open binding | Menu-command parity is the stronger convention for a data app; Return already opens the selection | Phase 16 |

---

# Known Issues

* None in the macOS project. (RN-side observations that constrain the port are listed in
  `DATA_ARCHITECTURE.md` §7 — they are parity constraints, not defects to fix silently.)
* **Decision item raised by Phase 13:** Reset Data keeps `quick_transactions` templates, exactly as
  the source does. The confirmation now says so, but if the desired behavior is to wipe templates
  too, that is a deliberate divergence from the source — see the Phase 13 "Issues / deviations".
* **Decision item raised by Phase 14:** the groups screen syncs on every open (its guard reads a key
  the pull never writes). Preserved for parity and converged the way the source converges it; if it
  should sync once, fix the *source's* key mismatch in both apps as a deliberate divergence.
* **Real-device verification outstanding:** Supabase auth and the sync engine are verified against
  fakes (574 green tests, protocol asserted end-to-end). A run against a live Supabase project
  (credentials in `Jmoney.xcconfig`) plus a real Touch ID lock/unlock cycle is the remaining
  manual check for Phase 18's parity audit.

---

# Next Agent Instructions

Phases 0–16 are complete and green (608 tests). Start **Phase 17 (accessibility / performance)** —
the brief is
in the "Current Phase" section above. It is a macOS-original feature (the RN app has none), so the
feature matrix's §12 row is the parity contract: document it as an addition, not parity. The one
remaining Phase 7 item is **location tagging** (create-time capture plus the location edit sheet);
carry it into Phase 15 or a follow-up, and create `Services/LocationService.swift` when you do.

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
* `SessionStore.userId` is the signed-in user's id to scope per-user queries by; `AppState.openReport(_:)`
  + `ReportDestination` handle cross-section links.
* `TransactionService` is the reference for entity work: `Filters` in, parameterized queries out,
  with a `Draft` → row factory for writes. Its tests show the in-memory `DatabaseQueue` fixture
  pattern — seed with a shared helper through `dbQueue.write`, then assert inside `dbQueue.read`
  (seeding inside a read transaction fails with SQLite error 8).
* `BudgetService` / `GoalService` are the closest references for the entity services (the
  meta entities): a list query, a per-row enrichment aggregate where needed, a stable sorted
  comparator, and `save`/`softDelete`. Their view models show the observed-sort reload pattern, and
  `InitialSyncGuard` is where any further first-open sync predicate belongs.
* Reports (Phase 10) is complete: `ReportService` is the reference for a **read-only aggregate**
  service (pure statics + parameterized queries, one `pool.read` per screen load), and
  `Features/Reports/` shows the config-driven-page pattern. Reuse `ReportService.sorted`'s stable
  comparator shape, `ReportService.drillDown`'s window selection, and `TransactionRow` for any
  transaction list. `ReportDestination` is now the full 11-report catalog.
* `Validators` (amount/transaction/budget/goal) and `Support/Formatters.swift` cover the shared
  formatting and validation rules; extend rather than duplicate.
* The four management entities (Phase 12) are done and are the reference for a **list screen with
  priorities**: `Support/EntityOrdering.swift` (shared search + name/priority sort + reorder
  renumbering), `Support/ViewModePreference.swift` (per-screen list/grid preference) and
  `Support/CategoryIcon.swift` (the one Material→SF Symbol table every category glyph goes through —
  do not fork a second one). `CategoryService`/`PayeeService` are add-only by design; `GroupService`
  hard-deletes the group row and nothing else; `QuickTransactionService` soft-deletes.
* `AppState.openTransactions(filters:)` is how another section opens a pre-filtered Transactions
  list, and `AppState.transactionEditor = .template(_)` opens the editor prefilled from a template
  (`TransactionService.prefill`).
* `AppState.dataRevision` / `markDataChanged()` is how a write tells open views to reload;
  `AppState.statusMessage` is the toast surface the RN screens use `showToast` for.
* Settings (Phase 13) is complete and is the reference for **device preferences and capability
  checks**: `Support/AppearancePreference.swift`, `ReminderPreference.swift`,
  `BiometricPreference.swift` and `SyncPreference.swift` hold the pure rules and the keys (the
  source's own AsyncStorage names); `BiometricGate` is the pure decision table and
  `Services/BiometricService.swift` / `NotificationService.swift` are the thin framework wrappers.
  `Services/SettingsService.swift` owns the six-table wipe and the exact 12-key teardown — if you
  touch reset behavior, `SettingsServiceTests` asserts both the list and the keys it must *not*
  clear. `SettingsViewModel` injects its capability calls, so follow that pattern when a flow needs
  hardware.
* **Sync/auth (Phase 14) is complete and is the reference for cloud work**: `SyncService` and the
  `Services/Sync/` modules are the exact protocol ports — do not alter their quirks without
  recording a deliberate divergence. `AppState.requestSync` / `requestTransactionSync(isPartial:)` /
  `requestEntitySync(_:)` / `requestEntityPush(_:userId:)` are the four request channels; `RootView`
  owns the runners and funnels every outcome into the status bar. `CloudFactory.make()` resolves
  config + services once at launch; an unconfigured build is a supported state with stubs.
  `Support/SyncPolicy.swift` holds the sync predicates; `SyncPreference` now also carries
  `now`, the groupService key accessor, and the initial-sync-checked flag helpers.
* **Commands (Phase 16)**: `AppCommands.menuAuditTable` is the shortcut set's single source of
  truth — the menu body builds from it and `CommandsTests` runs the standard-macOS conflict rules
  against it (the three deliberate plain-⌘ re-uses each carry their safety reason in the test).
  `AppSection.syncEntity` maps a section to its per-entity sync, and
  `AppState.requestSectionEditor` / `requestSectionSync` are the two request channels that section
  views answer only when frontmost (`selectedSection` guard).
* **Import/Export (Phase 15) is complete and is the reference for file exchange**:
  `Support/CSV.swift` (RFC 4180 encode/decode — mind the Swift grapheme-cluster CRLF trap:
  `"\r\n"` is one `Character`, match `case "\r", "\r\n"`), `Services/ExportService.swift`
  (transactions/categories/payees/goals CSV + the JSON backup of all seven tables with
  `sync_status`/`tid`/`deleted` verbatim), `Services/ImportService.swift` (name-mapped, per-row
  validated, born-dirty import), and the two sheets in `Features/Export/`. `AppState.showExportSheet`
  / `showImportSheet` present them; `AppState.transactionsFilters` is the live filter snapshot that
  makes "export what's on screen" possible. The import's atomicity relies on the **caller's**
  `pool.write` transaction (the `SettingsService.resetLocalData` pattern) — do not add a nested
  `db.inTransaction`.
* `BiometricPreference.isEnabled(in:)` gates the app lock; `BiometricService.unlock()` (password
  fallback allowed) is the lock prompt, `BiometricService.authenticate` (biometrics-only) is for
  the Settings enable flow. `AppLockView` is presented by `RootView`'s overlay — do not re-implement.
* `TransactionRow` is shared with the dashboard and the budget drill-down; keep new list renderers
  consistent with it.
* Tests: `JmoneyTests/` via `xcodebuild … test -destination 'platform=macOS'` (574 passing).
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

### Phase 10 Commit

`8d35677` — 2026-09-21 — "phase: implement reports" (hash recorded in a follow-up docs commit per
the established pattern).

### Phase 11 Commit

`ac40987` — 2026-09-21 — "phase: implement calendar" (hash recorded in a follow-up docs commit per

the established pattern).

### Phase 12 Commit

`850d0cc` — 2026-09-21 — "phase: implement categories, payees, groups and quick transactions" (hash
recorded in a follow-up docs commit per the established pattern).

### Phase 13 Commit

`a8f1ef2` — 2026-09-22 — "phase: implement settings" (hash recorded in a follow-up docs commit per
the established pattern). This phase also carried the third analysis re-verification pass — see the
Phase 13 section above.

### Phase 14 Commit

`c7aee09` — 2026-09-22 — "phase: implement authentication and sync" (hash recorded in a follow-up
docs commit per the established pattern). This phase carried the fourth analysis re-verification
pass — see the Phase 14 section above.

### Phase 15 Commit

`4947adc` — 2026-09-23 — "phase: implement import and export" (hash recorded in a follow-up docs
commit per the established pattern).

### Phase 16 Commit

`PENDING` — 2026-09-23 — "phase: audit and complete keyboard commands" (hash recorded in a
follow-up docs commit per the established pattern).
