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
| 13    | Settings                            | NOT STARTED |
| 14    | Authentication / Sync               | NOT STARTED |
| 15    | Import / Export                     | NOT STARTED |
| 16    | macOS commands / keyboard shortcuts | NOT STARTED |
| 17    | Accessibility / performance         | NOT STARTED |
| 18    | Final feature parity audit          | NOT STARTED |
| 19    | Release preparation                 | NOT STARTED |

---

# Current Phase

**Phase:** 13 — Settings

Phase 12 (Categories / Payees / Groups / Quick Transactions) is complete, built, and tested
(421 tests green — see the Progress Log). It also closed the Phase 7 quick-transaction-preset item.

Goal: the Settings screen and its scene — theme, daily reminders, Touch ID, manage-data entries,
manual sync, reset data, account email + sign out. Read `MACOS_FEATURE_MATRIX.md` §10 for the row
inventory and the specification in `app/(tabs)/settings/index.tsx` plus `src/hooks/useAppSettings.ts`,
`useBiometrics.ts`, `src/services/notificationService.ts` and `resetAppData` in `src/db/queries.ts`.

1. `Features/Settings/` currently holds only `SettingsPaneView` (which opens the ⌘, window) and
   `SettingsSceneView`. Phase 13 owns the real pane and the scene's contents.
2. Theme: the RN app stores `app_theme` (`light`/`dark`/`system`, defaulting to system). The macOS
   reading is a native appearance override (`.preferredColorScheme`) persisted in `UserDefaults`.
3. Reminders: `notificationService.ts` schedules a daily local notification titled "Reminder 💰"
   for 9:00 / 18:00 / 21:00 / Custom; map it to `UserNotifications` and decide the permission and
   "not determined" paths — document what you choose.
4. Biometrics: `useBiometrics.ts` verifies hardware **and** enrolment before enabling; macOS is
   `LocalAuthentication` (`canEvaluatePolicy` / `evaluatePolicy`). Keep the same gate order.
5. Manage-data entries (Goals / Categories / Payees / Groups / Quick Transactions) already exist as
   sidebar sections (`AppSection`), so Settings should link to them rather than duplicate them.
6. Manual full sync (⌘R / "Sync Now") and **Reset Data** are the two risky ones:
   * `AppState.requestSync()` currently reports "Sync isn't connected yet." Leave that until
     Phase 14, or wire it to a stub with an honest status message.
   * Reset Data must reproduce the source exactly, **including its quirk**: it deletes transactions,
     budgets, goals, categories, payees and transaction_groups, clears a specific list of sync keys
     — and does **not** delete `quick_transactions`, nor clear the quick-transaction / group-sync /
     view-mode keys. `DATA_ARCHITECTURE.md` §4 has the exact key list. Surface the quirk in the
     confirmation rather than silently "fixing" it, and flag it for a user decision.
7. Haptics has no Mac hardware: the matrix marks it MACOS EQUIVALENT → omit, and say so in the UI.

Still outstanding from Phase 7: **location tagging** on create plus the location edit sheet. The
quick-transaction presets item is now done (Phase 12 built the picker and the editor prefill);
`TransactionService.prefill` and `AppState.transactionEditor = .template(_)` are the pieces it built.

After 13: 14 (Authentication / Sync) — the biggest remaining phase, and the one every
`InitialSyncGuard` wrapper and `sync_status = 1` write from Phases 7–12 has been prepared for.

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

---

# Known Issues

* None in the macOS project. (RN-side observations that constrain the port are listed in
  `DATA_ARCHITECTURE.md` §7 — they are parity constraints, not defects to fix silently.)

---

# Next Agent Instructions

Phases 4–12 are complete and green (421 tests). Start **Phase 13 (Settings)** — full instructions in
the "Current Phase" section above, including the Reset Data quirk that must be reproduced and
surfaced. The only Phase 7 item still outstanding is **location tagging** (create-time tagging plus
the location edit sheet); the quick-transaction presets landed in Phase 12.

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
* `TransactionRow` is shared with the dashboard and the budget drill-down; keep new list renderers
  consistent with it.
* Tests: `JmoneyTests/` via `xcodebuild … test -destination 'platform=macOS'` (344 passing).
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

`PENDING` — 2026-09-21 — "phase: implement categories, payees, groups and quick transactions" (hash
recorded in a follow-up docs commit per
the established pattern).

<!-- The Phase 11 entry continues below; the Phase 12 entry above is the new one. -->

### Phase 11 Commit (continued)

the established pattern).
