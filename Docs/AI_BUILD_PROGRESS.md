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
| 6     | Dashboard                           | NOT STARTED |
| 7     | Transactions                        | NOT STARTED |
| 8     | Budgets                             | NOT STARTED |
| 9     | Goals                               | NOT STARTED |
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

**Phase:** 6 — Dashboard

Implement the dashboard over the Phase 5 data layer, reproducing the RN calculations exactly
(`DATA_ARCHITECTURE.md` §2 — formulas are normative):

1. `Services/DashboardService.swift`: pure, testable ports of `dashboardService.ts` —
   `processSummary`, `calculateDailyLimit` ((income − (expense − spentToday)) ÷ remaining days incl.
   today, floor 0, remaining = max(0, limit − spent), remaining% = remaining/(remaining+spent)×100),
   `calculatePayDayInfo` (daysInMonth − currentDay + 1, next payday `MMM 01`).
2. `DashboardViewModel` (`@Observable`): `fetchDashboardMetrics` — month MTD, prev-month MTD
   comparison (same day-of-month), year YTD + prev-year YTD (same day), net worth, spent today,
   top-3 expense categories — mirroring the parallel fetch in `dashboardService.ts`.
3. Widgets in `Features/Dashboard/`: daily limit card (+ drill-down to "Today's Activity" — the
   RN `daily-limit-detail` screen: spent today + today's transaction list), month-remaining card,
   pay-day card, top categories, This Month / This Year summary cards (click-through to the
   Monthly/Yearly Summary report views), net-worth card.
4. Unit tests first for the pure calculations (daily limit edge cases: zero income, overspend,
   spent = 0 → 100%; pay day; processSummary type mapping).
5. Widgets render zero-values with the local (empty) DB; the first-launch sync modal stays a
   Phase 14 item.

After 6: 7 (Transactions — list/filters/editor on GRDB) → remaining phases per the matrix.

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

---

# Known Issues

* None in the macOS project. (RN-side observations that constrain the port are listed in
  `DATA_ARCHITECTURE.md` §7 — they are parity constraints, not defects to fix silently.)

---

# Next Agent Instructions

Phases 4 (shell) and 5 (data layer) are complete and green. Start **Phase 6 (Dashboard)** — full
instructions in the "Current Phase" section above. Summary:

1. Port the pure calculations first (`Services/DashboardService.swift` from `dashboardService.ts`)
   with unit tests before touching UI — formulas are normative in `DATA_ARCHITECTURE.md` §2.
2. `DashboardViewModel` (`@Observable`) runs the metric queries against `DatabaseService.pool` on a
   read connection; use GRDB `ValueObservation` where it simplifies refreshes.
3. Replace `DashboardView`'s placeholder with the widget stack (daily limit + Today's Activity
   drill-down, remaining, pay day, top categories, This Month/This Year with click-through to the
   report views, net worth). Keep the empty-DB zero state readable.
4. Keep the sync modal out (Phase 14); ⌘R still reports "not connected".
5. `xcodegen generate` after any file addition; build + test green before committing.

Existing infrastructure (don't redo):

* `DatabaseService` (`@Observable`, `.environment`-injected; `prepare()` idempotent from
  `RootView.task`). Pool access: `database.pool` after `prepare()`, error in `initializationError`.
* DTOs in `Models/` map columns 1:1; `Transaction` carries the denormalized name columns.
* `TransactionTimestamp` (`Support/Timestamps.swift`) for all timestamp derivations — do not
  re-implement with different semantics.
* Tests: `JmoneyTests/` via `xcodebuild … test -destination 'platform=macOS'` (21 passing).
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
