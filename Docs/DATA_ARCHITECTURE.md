# Jmoney macOS — Data Architecture

> Populated after analyzing the React Native application's database, offline-first behavior,
> synchronization, and Supabase integration. Last updated: 2026-09-23 (Phase 17: the §1.2 index set
> is now proven load-bearing — `PerformanceTests` asserts via `EXPLAIN QUERY PLAN` that the
> screens' queries run through these indexes, and pins list/filter/dashboard/report correctness
> on a 10,000-row ledger; §8's verification record is unchanged).

## Status

Analysis complete (§8). **Persistence implemented (Phase 5)**: `Services/DatabaseService.swift`
opens a WAL `DatabasePool` and migrates to the exact schema in §1.2–§1.3 (verified by tests:
tables, columns, defaults, composite index column order, quick-transactions born-dirty quirk).
DTOs in `Models/` match every column name. `Support/Timestamps.swift` ports `transactionTimestamp.ts`
byte-compatibly, and adds `instant(from:)` (the JS `new Date(ts).getTime()` used for ordering) and
`utcISOString(from:)` (JS `toISOString()`, used when saving). **Read path implemented (Phase 6)**:
`Services/DashboardService.swift` carries the dashboard's parameterized aggregations
(`incomeExpenseSummary`, `expensesByCategory`, `netWorth`, `spentToday`, `transactions(userId:date:)`)
alongside the pure calculations. **Transaction path implemented (Phase 7)**:
`Services/TransactionService.swift` carries the filtered list, the day-section mapping, the
five-month statistics, the lookups, and the write path (`save` upsert + `softDelete`). **Budget path
implemented (Phase 8)**: `Services/BudgetService.swift` carries the month spending aggregate, the
`categories` JSON column codec, the four sort orders, the month-range bounds (`minTransactionDate`,
`canGoToPreviousMonth`/`canGoToNextMonth`, `isMonthSelectable`, `selectableYears`), the drill-down,
and the write path. **Goal path implemented (Phase 9)**: `Services/GoalService.swift` carries the
progress maths, the three sort orders, the fetch, and the write path (`save` upsert + `softDelete`).
**Management-entity path implemented (Phase 12)**: `Services/CategoryService.swift`,
`PayeeService.swift`, `GroupService.swift` and `QuickTransactionService.swift` carry the four
lists (with the source's `priority ASC, name ASC` order), their filters/sorts, the `MAX(priority)+1`
auto-assignment, the upserts, `updatePriorities`, and each table's own delete shape (group hard
delete, quick-transaction soft delete, categories/payees none). **Sync engine implemented
(Phase 14)**: `Services/SyncService.swift` (the `syncService.ts` coordinator — push-all,
seven ordered pulls, the source's progress strings, the `isSyncing` re-entrancy guard, the master
timestamp written only on success) plus `Services/Sync/` — one module per entity porting
`src/services/sync/*` exactly, including every quirk in §3–§4 (budget interval normalization and
the empty-category skip, the `is_living_cost` strip, the quick-transaction pull's `deleted = 0`
filter, the group key mismatch, the transaction pull's sentinel values and 1000-row `tid` paging,
the push-before-wipe force resync). `Services/Auth/` + `Stores/SessionStore.swift` port
`AuthContext.tsx` (7-second restore guard, local-data-preserving sign-out) over `supabase-swift`
with Keychain session storage; credentials come from `Jmoney.xcconfig` → Info.plist →
`SupabaseConfig` (§3.5), and an unconfigured build degrades to honest stubs instead of crashing.
**File exchange implemented (Phase 15 — macOS-original, no RN counterpart)**: `Support/CSV.swift`,
`Services/ExportService.swift` and `Services/ImportService.swift` carry the CSV/JSON data contract
in §9 — schema-named columns, name-based entity mapping, sentinel handling, and born-dirty imports
that ride the existing sync protocol unchanged.

---

## 1. Existing React Native Data Architecture (source of truth)

### 1.1 Local store

- **Engine**: expo-sqlite, database file `jmoney.db`, `PRAGMA journal_mode = WAL`.
- **Ownership rule**: local SQLite is the single source of truth for the UI. Supabase is the
  cloud copy used for auth + cross-device sync. Nothing in the UI waits on the network.
- **Boot**: `initDB()` must complete before navigation renders.

### 1.2 Tables (columns as implemented in `src/db/database.ts`)

**transactions**
`id TEXT PK, amount REAL, description TEXT, transaction_timestamp TEXT (ISO local),
date TEXT (yyyy-MM-dd, derived from timestamp), category_id TEXT, category_name TEXT,
category_icon TEXT, category_app_icon TEXT, payee_id TEXT, payee_name TEXT, payee_logo TEXT,
type TEXT ('Income'|'Expense'), user_id TEXT, product_link TEXT, tid INTEGER (server sequence,
0 until first push), latitude REAL, longitude REAL, sync_status INTEGER (1 = dirty),
created_at TEXT, updated_at TEXT, deleted INTEGER (soft delete), group_id TEXT, group_name TEXT`

> Names (`category_name/icon/app_icon`, `payee_name/logo`, `group_name`) are **denormalized onto the
> transaction row** for fast list rendering without joins; they are populated from joins during
> pull and from the selected entity during save.

**goals**: `id, name, logo, goal_amount REAL, current_amount REAL, user_id, sync_status, deleted`
**budgets**: `id, name, logo, amount REAL, interval TEXT, start_date TEXT,
categories TEXT (JSON array of category IDs), user_id, sync_status, deleted`
**categories**: `id, name, type ('Income'|'Expense'), icon, app_icon, user_id,
is_living_cost INTEGER, priority INTEGER, sync_status`
**payees**: `id, name, logo, user_id, priority INTEGER, sync_status`
**quick_transactions**: `id, name, type, amount, category_id, payee_id, description, user_id,
product_link, priority INTEGER, identifier TEXT, sync_status, deleted`
**transaction_groups**: `id, name, description, user_id, priority INTEGER, sync_status`

### 1.3 Indexes

`transactions(date)`, `(type)`, `(category_id)`, `(user_id)`, `(sync_status)`, `(category_name)`,
`(tid)`, `(group_id)`, plus composite `(user_id, deleted, date)`, `(user_id, deleted, category_id)`,
`(user_id, deleted, payee_id)`.

### 1.4 Migrations

`CREATE TABLE IF NOT EXISTS` + idempotent `ALTER TABLE ADD COLUMN` list with errors swallowed.
No schema-version table. The macOS port should implement a proper `PRAGMA user_version` migration
chain instead (documented improvement, not a behavior change).

### 1.5 Preferences store (AsyncStorage in RN → UserDefaults/Keychain in macOS)

- `@last_sync_<entity>_<userId>` — per-entity last sync ISO timestamps
  (transactions, categories, payees, budgets, goals, quick transactions, transaction_groups)
- `@last_sync_master_<userId>` — last full sync
- `@initial_<entity>_sync_checked_<userId>` — first-sync guard flags
- `app_theme`, `use_biometrics`, `notification_pref`, haptics setting,
  `reports_view_mode`, per-management-screen view modes
- Sync config: batch 100, retry 3, interval 5 min (constants; interval not observed as a timer)

## 2. Business Rules & Calculations (must be reproduced exactly)

| Rule | Definition (from source) |
| --- | --- |
| Net worth | `SUM(CASE type WHEN 'Income' THEN amount ELSE -amount END)` over all non-deleted transactions |
| Spent today | `SUM(amount)` where type='Expense' and date = today |
| Daily limit | `(month.income − (month.expense − spentToday)) ÷ remainingDaysInMonth` (incl. today); floor 0; `remaining = max(0, limit − spentToday)`; `remaining% = remaining/(remaining+spent)×100`; both-zero ⇒ 100%; clamped 0…100 |
| Daily-limit remaining days | `remainingDaysInMonth` = `daysInMonth − currentDay + 1` — equal to the source's `differenceInDays(endOfMonth(today), today) + 1`, but calendar-exact. Implemented as `DashboardService.calculateDailyLimit` |
| Pay day | `daysInMonth − currentDay + 1` days remaining; next payday label `MMM 01` |
| Dashboard comparisons | Month MTD vs same-day previous month; year YTD vs same-day previous year. `DashboardService.dateWindows` derives: month MTD `[monthStart, today]`, month totals `[monthStart, monthEnd]` (used only for top categories), previous month `[prevMonthStart, prevMonthSameDay]`, previous year `[prevYearStart, prevYearSameDay]`. Every window is an inclusive `yyyy-MM-dd` string comparison (`date >= ? AND date <= ?`) |
| Previous-period day clamping | `subMonths`/`subYears` clamp an overflowing day onto the target month's last day (Mar 31 − 1 month = Feb 28; Feb 29 − 1 year = Feb 28). Foundation's date arithmetic does **not**, so `DashboardService.subtracting` implements the clamp explicitly |
| Budget spending | `SUM(amount)` of expenses in period where `category_id IN (budget's category JSON)`. Implemented as `BudgetService.spending` with bound parameters (the RN code interpolates); an empty category set spends 0 and a NULL sum reads as 0. The drill-down is a *different* query: it is not expense-only and not exclusive of income, so its rows can total more than the card's spent figure |
| Budget month bounds | Navigation runs from the month of `MIN(date)` over non-deleted transactions (falling back to **today** when there is no history, so a fresh account cannot page back) up to the current month end. `endOfMonth(subMonths(selectedDate,1)) >= startOfMonth(minDate)` gates "previous"; `startOfMonth(addMonths(selectedDate,1)) <= endOfMonth(maxDate)` gates "next" |
| Budget sort | `name` uses locale collation (`localeCompare`); `amount`, `spent` and `remaining` compare numerically, where remaining is `(a.amount − a.spent) − (b.amount − b.spent)`. `Array.prototype.sort` is stable, so equal keys keep the `ORDER BY name` order — restored explicitly in Swift |
| Goal progress | `current_amount / goal_amount` — the sort key uses the unclamped ratio; the card clamps the *percentage* to 100, rounds it for display, and floors `remaining` at 0. `goal_amount = 0` yields 0 rather than dividing. Implemented as `GoalService.cardInfo` / `progressRatio` |
| Report comparison | diff% = (current − previous)/previous × 100; previous matched by name/type; MTD-vs-MTD or YTD-vs-YTD for current period, full-vs-full otherwise; new items with no previous show +100%. Windows clamp an overflowing day onto the target month's last day (31 Mar MTD ends 28/29 Feb) instead of rolling forward as the JS `Date` constructor does — see the Phase 10 note below |
| Report total vs previous total | The banner's `totalAmount` sums the **filtered/sorted** rows, but `previousTotal` sums the **unfiltered** ones, so a search changes the trend's numerator but not its denominator. `payees`/`categories` always report a 0 total diff. Implemented as `ReportService.present` |
| Report drill-down window | `payees`/`categories` scan all time (`1970-01-01`…`2099-12-31`), the yearly reports the whole selected year, everything else the selected month. `subscriptionAndBills` additionally filters by category name only and ignores the row's type. Preserved inconsistency: the **groups overview lists all-time totals while its drill-down uses the month window** |
| Report search/sort | Search matches `name`/`category_name`/`payee_name` (no `group_name`); sort is `name` or `amount`, with a group-priority override that applies only when *both* rows carry a priority and is not reversed by the sort direction. `Array.prototype.sort` stability restored explicitly |
| Living costs | `categories.is_living_cost` is a local-only flag: it is stripped on push and omitted on pull, so it resets to 0 after a full pull. The report's configuration sheet writes it **without** setting `sync_status = 1`, since a dirty flag would create a pointless push |
| Filtered total | Σ(income − expense) over the active transaction filter |
| Calendar day total | Σ(income − expense) for the selected date. Rendered with a `+` prefix when not negative and **no** sign when negative (the currency helper drops it), with colour carrying the direction |
| Calendar period rules | Two day rules coexist because the source uses both: an explicit period pick keeps the selected day number but sends a day that does not fit the new month to the **1st** (`newDay = currentDay > daysInNewMonth ? 1 : currentDay`), while a stepper step clamps onto the month end (date-fns `subMonths`). Navigation is bounded by `MIN(date)` (falling back to today, so a fresh account cannot page back) and the end of the current month. The grid is **Sunday-first** (date-fns' default), unlike the Monday-first week the transaction quick ranges force |
| Earliest transaction date | `MIN(date)` over non-deleted transactions, falling back to **today**. Shared by budgets, reports and the calendar as `TransactionBounds.minDate` — the source parses the column value with `new Date('yyyy-MM-dd')`, i.e. **UTC midnight**; the port parses it in the calendar's zone so the earliest month cannot shift by a day in a negative-offset time zone |
| Search | numbers → exact amount match; otherwise LIKE on description and amount-as-text. The numeric form is `^-?\d+(\.\d+)?$`, and when it matches the LIKE is **not** run at all (so `5` does not match a description containing "5"). Exception: `getMonthlyFilteredStats` never takes the numeric branch — its search is always the LIKE, so there `50` *does* match "500 note electricity" |
| Sorting | Transactions: date desc then `transaction_timestamp` desc. Entities: `priority ASC, name ASC` default; user-selectable sorts per screen (see matrix) |
| Defaults | New expense → category "general"; new income → category "salary" (case-insensitive name match). A **quick-transaction prefill is exempt**: the source guards that effect with `!quickTx`, so a template with no category leaves the picker empty |
| Quick-transaction prefill | Selecting a template prefills type, amount, description, category and payee (each only when the template has it, and only when the referenced category/payee still exists). Three preserved quirks: the template's `product_link` is **never** applied, no group is set, and the date stays "now" |
| Priority auto-assignment | A new category/payee/group/quick-transaction with `priority = 0` gets `MAX(priority) + 1` over **all** rows of that table for the user (including soft-deleted templates). An existing row keeps its priority on edit. Reordering renumbers the **visible set** from 1, so the Expense and Income tabs renumber independently and can collide — harmless, since the two lists are never shown together |
| Management list ordering | `priority ASC, name ASC` for categories, payees, groups and quick transactions (quick transactions additionally filter `deleted = 0`). The user-selectable sorts are `name` (locale collation) or `priority`, either direction, with `Array.prototype.sort` stability restored — reorder mode ignores the choice and forces ascending priority. Quick transactions have no sort menu: always `priority ASC` |
| Management search | Case-insensitive substring over the entity's name — plus the description for **groups only**. The gate is `searchQuery.trim()` but the needle is the *untrimmed* lowercase query, so a trailing space can only match text with a space there; quick transactions are the exception and trim their needle |
| Category icon | `categories.app_icon` holds a **Material** icon name (free text). macOS maps it through one curated table (`Support/CategoryIcon.swift`); the source's `formatIconName` (strip a leading `Md`, kebab-case camelCase) and its per-context empty defaults (`category` for a category, `receipt` for a transaction/report row, `category_app_icon \|\| app_icon \|\| receipt` for a report row) are reproduced. `''` and an unmapped name both fall back to a neutral glyph |
| Validation | amount > 0 and ≤ 999,999,999; description ≤ 500 chars; category required; goal name required + current ≥ 0; budget name + ≥1 category + amount valid |
| Timestamps | `transaction_timestamp` written at save via `date.toISOString()` (**UTC, 'Z' suffix**); `date` column = local calendar `yyyy-MM-dd` derived at save. On push to Supabase the timestamp is converted to the device's **local wall-clock without suffix** (`yyyy-MM-dd'T'HH:mm:ss.SSS`); on pull `date` is re-derived from the raw string prefix (`getTransactionDate` matches `^(\d{4}-\d{2}-\d{2})[T ]`). Net effect: after the first push/pull cycle timestamps are local wall-clock; before that, a pulled row's `date` can differ from the source device's local date near midnight |
| Currency | `₹`, locale `en-IN`, 0 or 2 fraction digits |

## 3. Synchronization Protocol (preserve exactly)

### 3.1 Status fields
- `sync_status`: `1` = local change not yet pushed, `0` = in sync.
- `deleted`: `1` = soft-deleted pending push (transactions, goals, budgets, quick transactions;
  categories/payees/groups have no `deleted` column).

### 3.2 Push (local → Supabase)
1. Select rows with `sync_status = 1` for the user.
2. If `deleted = 1`: `DELETE` on Supabase by id, then hard-delete the local row.
3. Else: `UPSERT (onConflict: id)`; for transactions, capture the returned server `tid` and store it
   locally with `sync_status = 0`.

Entity-specific push details (verified in source):
- **Budgets**: `interval` normalized `'Monthly'` → `'Month'` before push (Supabase constraint);
  `categories` JSON string → array; budgets whose category array is empty are **silently skipped**
  (logged only) and remain `sync_status = 1` forever.
- **Categories**: `is_living_cost` is stripped from the push payload (local-only field, see §4).
- **Transactions**: `payee_id`/`group_id` holding the literal string `'null'` are converted to real
  `NULL` before push.

### 3.3 Pull (Supabase → local)
- **Meta entities** (goals, budgets, categories, payees, quick transactions, groups): *full replace* —
  delete all local rows for the user, then insert everything from Supabase with `sync_status = 0`.
  One deviation: the **quick-transactions pull deletes only `deleted = 0` rows**, so locally
  soft-deleted-but-unpushed presets survive a pull (defensive; every sync pushes before pulling).
  The categories pull insert omits `is_living_cost`, so the flag resets to `0` on every pull (see §4).
- **Transactions**: *incremental* — pull rows with `tid > MAX(local tid)`, ordered by `tid`,
  chunked at 1000, using server-side joins to denormalize category/payee/group names. Insert/replace
  with `sync_status = 0` and locally-derived `date`.
- **Force resync**: delete all local transactions for the user, then full incremental-style re-pull
  from `tid = 0`.

### 3.4 Coordination
- `runFullSync(userId)`: connectivity check → push all entities → pull transactions → pull each meta
  entity in fixed order (transactions, goals, budgets, categories, payees, quick transactions,
  groups) → write `@last_sync_master_<userId>`. Progress strings surfaced to UI. Re-entrancy guarded
  by a module-level flag.
- Per-screen auto-sync: after save/delete, and on focus when `!lastSync` (first-run) or
  `localMaxTid < remoteMaxTid` (`needsTransactionSync`).
- Connectivity: NetInfo (`isConnected && isInternetReachable`) → NWPathMonitor on macOS.
- Per-entity timestamps recorded after each successful pull.

### 3.5 Supabase
- Tables mirror the local ones (Postgres, `user_id` scoped, RLS implied by per-user queries).
- Transactions table has server-generated sequential `tid` (returned by upsert via `.select('tid')`).
- Auth: Supabase email/password; session persisted (AsyncStorage in RN → Keychain in macOS);
  auto-refresh tokens.
- **Configuration**: the RN app hardcodes the project URL and anon key in `src/services/supabase.ts`.
  The macOS app must NOT copy secrets into source; pass them via build configuration
  (`INFOPLIST_KEY`/xcconfig or `.xcconfig` + Info.plist). The anon key is public-by-design but still
  treated as configuration, not code.

## 4. Local-only Behaviors to Preserve

- **Reset Data** (`resetAppData`): single transaction deleting all rows for the user from
  `transactions`, `budgets`, `goals`, `categories`, `payees`, `transaction_groups`, then clearing
  sync flags/prefs. ⚠️ It does **not** delete `quick_transactions` — replicate this quirk for parity
  and surface it to the user as a decision item in a later phase.
  Exact AsyncStorage keys cleared (verified in `useAppSettings.ts`): `notification_pref`,
  `@last_sync_master_`, `@last_sync_transactions_`, `@last_sync_budgets_`, `@last_sync_goals_`,
  `@last_sync_categories_`, `@last_sync_payees_`, `@initial_budget_sync_checked_`,
  `@initial_goals_sync_checked_`, `@initial_categories_sync_checked_`,
  `@initial_payees_sync_checked_`, `reports_view_mode`. It does **not** clear
  `@last_sync_quick_transactions_`, `@last_sync_transaction_groups_`, `@last_sync_groups_`, or any
  per-user view-mode keys (`@category_view_mode_`, `@payee_view_mode_`, `@group_view_mode_`,
  `@quick_transaction_view_mode_`). `SettingsService.resetStorageKeys` is that exact list, and
  `SettingsServiceTests` asserts both the list and the survivors so neither drift silently.
  Two behaviour notes for the port: the key sweep is the *only* thing reset does to settings, so
  `app_theme` and `use_biometrics` survive a reset (as in the source) — the appearance store is
  re-read afterwards for that reason; and the source clears `notification_pref` **without**
  cancelling the scheduled OS reminder, so a reset app would still deliver reminders while the row
  reads "Off". macOS cancels the pending reminder here — the one deliberate addition to the reset
  path (`SettingsViewModel.resetData`).
- **Settings preference keys** (`app_theme`, `use_biometrics`, `notification_pref`) are device
  preferences, not synced data: no sync module reads or writes them, and Supabase has no
  counterpart. `notification_pref` is the one with a subtlety — the source *removes* the key when
  the choice is `None` (`scheduleReminder` calls `removeItem`), so "no reminder" and "never
  configured" share a single stored state. `ReminderPreference` reproduces that, and also the
  scheduler's default branch: only `Evening`, `Night` and an `HH:mm` value set the hour, so an
  unrecognized value silently lands on 9:00.
- **`is_living_cost` is local-only**: the category push strips it and the pull insert omits it, so
  the flag **resets to `0` after every full pull** — the Living Costs report silently loses its
  selection after sync. Replicate for parity, but flag to the user as a candidate fix.
- **Priority auto-assignment**: new categories/payees/groups/quick-transactions get
  `priority = MAX(priority) + 1` when created without an explicit priority.
- **Group deletion** hard-deletes only the group row; member transactions keep a dangling `group_id`
  (filters/reports tolerate this by joining names).
- **Category/payee deletion** is not exposed in the RN UI; do not add destructive paths without
  flagging them as new behavior. The Phase 12 port therefore ships both screens **add-only**:
  neither table has a `deleted` column, so a local hard delete would be silently resurrected by the
  next full-replace pull (§3.3). Renaming has the same problem in reverse — a rename could not be
  represented as a delete — so neither is offered, exactly as in the source.
- **Quick-transaction `|| null` idioms**: an empty `description`, an empty `product_link`, an empty
  `identifier` and a **zero** amount all become SQL `NULL` (`0 || null` is `null`), so a template's
  amount is "set or flexible", never zero. `identifier` is upper-cased and truncated to two
  characters before storage.
- **Group last-sync key mismatch**: `groupService` reads/writes `@last_sync_groups_` while
  `groupSync.ts` writes `@last_sync_transaction_groups_`. The groups screen's "never synced"
  auto-sync check therefore reads a key the sync module never writes. Preserve the observable
  behavior (sync runs on first open); do not copy the key confusion.
- Sync-status fields must never be user-visible data; they are protocol internals.
- The `TABLES` constant also names `profiles`, `attachments`, `sync_log` — Supabase-side references
  only, with no local tables. Do not create local equivalents.

## 5. macOS Persistence Decision

**Decision: SQLite via GRDB.swift (SPM), mirroring the existing schema and sync protocol.**

Rationale:

1. **Proven schema & queries**: every business calculation is already expressed as SQL aggregation
   over this schema (net worth, budget spending, 11 reports, filtered stats). Porting to GRDB keeps
   the SQL nearly verbatim and testable against the same expectations.
2. **Sync protocol fidelity**: `sync_status`, `deleted`, `tid` cursors, and full-replace pulls are
   relational patterns that map 1:1.
3. **Offline-first + large datasets**: WAL mode, the existing composite indexes, and server-side
   chunking carry over directly; GRDB adds safe concurrent readers/writers on background queues.
4. **SwiftData rejected**: no raw-SQL aggregation control, weaker story for incremental sync columns
   and upsert semantics; would force re-deriving behavior in memory.
5. **Core Data rejected**: heavyweight object-graph mapping for a document-like ledger with complex
   aggregates; migration story adds risk without benefit here.

Implementation notes for Phase 5:

- Single `DatabasePool` (WAL), background writer queue; UI reads via `ValueObservation`.
- Migrations via `DatabaseMigrator` with `PRAGMA user_version`-equivalent identifiable migrations
  (v1 = the schema above + indexes).
- All SQL parameterized (fix the RN code's string-concatenation habits — several RN queries
  interpolate user strings into SQL; macOS must use bound parameters everywhere).
- DTOs matching the tables exactly (column names preserved) so sync mapping stays mechanical.
- Supabase access via `supabase-swift`; credentials injected from build configuration.

## 6. Data Flow Summary

```
UI (SwiftUI) ──reads──▶ GRDB ValueObservation ──▶ SQLite (WAL)
     │writes                                        ▲
     ▼                                              │pull (tid cursor / full replace)
Service ──write (sync_status=1)──▶ SQLite           │
     │                              SyncService ────┘
     └──background push (sync_status=1 / deleted)──▶ Supabase (Postgres + Auth)
```

## 7. Risks / Notes for Implementers

- `INSERT OR REPLACE` in RN deletes-then-inserts rows (fires replace semantics); when porting, use
  explicit upserts (`INSERT ... ON CONFLICT DO UPDATE`) to avoid surprising row churn.
- Transactions carry denormalized display columns; after any category/payee/group rename the
  transaction copies become stale (RN behaves the same; do not "fix" silently).
- `payee_id`/`group_id` can hold the literal string `'null'` in old data; RN filters these out
  (`!= 'null'`, `!= 'undefined'`, `!= ''`) in several queries — replicate the guards.
- Keep `date` and `transaction_timestamp` semantics byte-compatible with `transactionTimestamp.ts`
  to avoid cross-device date drift (see the Timestamps row in §2 for the exact UTC→local pipeline).
- New quick-transaction rows are born dirty: the migration adds `sync_status` to
  `quick_transactions` with `DEFAULT 1`, so they push on the first sync after install/upgrade.
- Goals have no `priority` column; the goals list default sort is `name ASC` (unlike every other
  management list, which defaults to `priority ASC, name ASC`).
- The report comparison windows are the one place the port **deliberately changes a source result**.
  `reportService.ts` builds them with `new Date(y, m, d)`, which rolls day overflow forward: an
  MTD-vs-MTD window for 31 March ends on 3 March of the previous month, and a leap day makes the YTD
  window end on 1 March. Both are meaningless as comparison bounds, so the day is clamped to the
  target month's length instead (the same decision Phase 8 made for `setMonth`). `previousPeriod`
  carries the details; the clamping cases are tested.
- The reports phase's only write is `is_living_cost` (`ReportService.setLivingCost`). Do not add
  `sync_status = 1` to it: the column never leaves the device, so it must not create a push cycle.
- Management-list writes: `CategoryService.updatePriorities` / `PayeeService.updatePriorities` /
  `GroupService.updatePriorities` / `QuickTransactionService.updatePriorities` flag `sync_status = 1`
  (the source pushes the reorder) but deliberately do **not** touch any other column — in particular
  `is_living_cost` survives a reorder. `GroupService.hardDelete` is the only hard delete in the app,
  and it removes the group row alone; `QuickTransactionService.softDelete` follows the standard
  soft-delete-then-push-delete path (§3.2).
- The category icon mapping is a **display-only** translation. Never write an SF Symbol name into
  `categories.app_icon` or `transactions.category_app_icon`: those columns carry Material names that
  the sync layer exchanges verbatim with Supabase.

## 8. Verification Record (second agent, 2026-09-20; re-verified 2026-09-22)

The Phase 1 analysis was independently re-verified by reading the actual RN source (not the docs):
all 7 sync modules, all 8 query modules, `database.ts`, `dashboardService`, `transactionService`,
`reportService`, `budgetService`, `goalService`, `calendarService`, the 4 entity services,
`AuthContext`, `useDashboardData`/`useDashboardSync`/`useBiometrics`/`useAppSettings`, all utils,
models, constants, `package.json`, and the main screens (`_layout`, tabs, transactions, dashboard,
settings, reports index, add-transaction).

Confirmed unchanged from the original analysis: schema/indexes, push/pull protocol and full-sync
order, `tid` cursor + 1000-row chunking, all §2 formulas, validators, search semantics, the
`'null'`/`'undefined'` guards, 11-report inventory and comparison logic, `resetAppData` quirk,
auth 7s timeout, biometric hardware/enrollment checks, reminder times (9:00/18:00/21:00/Custom),
and `ajv` being an unused dependency (0 references in `src/` and `app/`).

Additions found during re-verification are folded into §2–§4 above: the UTC-at-save timestamp
pipeline, budget push normalization/skip rules, quick-transaction pull deviation, `is_living_cost`
being local-only (resets on pull), priority auto-assignment, the group last-sync key mismatch, and
the exact reset-data key list.

### Third pass (2026-09-22, the Phase 13 agent)

Re-read directly from source: `app/(tabs)/settings/index.tsx`, `src/hooks/useAppSettings.ts`,
`src/hooks/useBiometrics.ts`, `src/services/notificationService.ts`, `src/db/queries.ts`
(`resetAppData`), `src/store/ThemeContext.tsx`, `src/store/AuthContext.tsx`, plus spot-checks of
`src/db/database.ts` (every `CREATE TABLE`, `ALTER TABLE` and `CREATE INDEX`) and the sync claims
in §3.2–§3.4. **Verdict: the documentation is accurate.** The reset key list, the six-table wipe
and its omission of `quick_transactions`, the `is_living_cost` strip, the `Monthly`→`Month` budget
normalization, the `@last_sync_groups_` vs `@last_sync_transaction_groups_` mismatch, the
quick-transactions born-dirty `DEFAULT 1`, and all 11 indexes (including the composite column order)
match the code exactly.

One wording correction was made. `AI_BUILD_PROGRESS.md`'s Phase 13 brief described the theme as
storing `light`/`dark`/`system`; the source only ever **stores** `"light"` or `"dark"`. `system` is
the behavior of an **absent** key (`ThemeContext` falls back to `Appearance.getColorScheme()`), and
the settings screen offers no way back to it. `MACOS_FEATURE_MATRIX.md` §10 already said this
correctly; the brief was corrected to match, and `AppearancePreference` models `System` as the
absent state.

### Fourth pass (2026-09-22, the Phase 14 agent)

Re-read directly from source before finishing Phase 14: `src/services/syncService.ts`, all seven
modules in `src/services/sync/` (`transactionSync.ts`, `budgetSync.ts`, `goalSync.ts`,
`categorySync.ts`, `payeeSync.ts`, `quickTransactionSync.ts`, `groupSync.ts`) and `baseSync.ts`,
`src/store/AuthContext.tsx`, `src/hooks/useBiometrics.ts`, `src/components/BiometricLock.tsx`,
`app/_layout.tsx` (the lock lifecycle), and the sync call sites in every screen (`app/goals.tsx`,
`app/(tabs)/budgets/index.tsx`, `app/categories.tsx`, `app/payees.tsx`, `app/groups.tsx`,
`app/quick-transactions.tsx`, `app/(tabs)/transactions/index.tsx`,
`app/(tabs)/dashboard/index.tsx`, plus `fetch<Entity>Data`/`perform<Entity>Sync`/
`backgroundPush*` in the four entity services and `handleBudgetSync`/`handleGoalSync`).

**Verdict: the sync/auth documentation (§1.5, §3, §4) is accurate**, and it matched the already-
ported `Services/Sync/` engine line for line — including every deliberate quirk. Findings that
were *not* yet documented and are now reflected in the macOS implementation:

1. **`performGroupSync` re-stamps the groupService key.** The groups screen's never-synced guard
   and its `performGroupSync` both use `@last_sync_groups_` (§4's key mismatch), so after the
   first open the guard converges — the service's stamp, not the pull's, is what stops the
   re-firing. The port reproduces this: a groups sync writes both keys.
2. **Manual sync buttons exist on all six management screens**, not just budgets/goals:
   categories, payees, groups and quick transactions each have a header refresh running
   `perform<Entity>Sync`, each with its own success toast. All six are ported (`ManagementSyncButton`).
3. **The categories/payees/groups/quick-transactions first-open checks are timestamp-only**
   (`!lastSynced || !lastSynced.includes('T')` in each `fetch<Entity>Data`) — no `alreadyChecked`
   flag in the condition, unlike budgets/goals. Ported as `SyncPolicy.needsTimestampOnlySync`.
4. **Reorder-exit pushes** (`backgroundPush{Categories,Payees,Groups,QuickTransactions}`) push only
   and re-stamp the per-entity last-sync key from the caller; ported as
   `SyncService.pushEntity` + `AppState.requestEntityPush`.
5. **Post-write syncs**: goals and budgets sync after save *and* delete
   (`handleGoalSync`/`handleBudgetSync`, which also write the `@initial_*_sync_checked_` flags);
   transactions fire a partial `syncTransactions` after save and delete. Ported through the same
   `AppState` request channels.
6. **The lock's prompt differs from the enable flow's**: `BiometricLock` passes
   `disableDeviceFallback: false`, so the OS password fallback is allowed — on macOS that is
   `.deviceOwnerAuthentication` for the lock, while the enable flow keeps
   `.deviceOwnerAuthenticationWithBiometrics`.

The one new implementation in this pass that has no source counterpart is the groups *service-key*
stamp in `SyncPreference.groupServiceLastSyncKey` — it exists to reproduce the convergence in
finding 1 without renaming the (load-bearing) sync-module key.

## 9. File Exchange Data Contract (Phase 15 — macOS-original)

The RN app has no import/export (§12 of the feature matrix; the README's claim was verified untrue
in code), so this section has **no parity contract** — but everything here respects the sync
protocol in §3, so imported data flows to Supabase exactly like user-entered data.

### 9.1 CSV (transactions)

* Header = the `transactions` schema's snake_case column names, in table order
  (`ExportService.transactionCSVHeader`). Optional columns render as empty strings; numbers are
  plain `String(Double)` descriptions — no currency grouping.
* Export is per-user and respects `deleted = 0`; the filtered export reuses the Transactions
  screen's live `Filters` (snapshotted on `AppState.transactionsFilters` at every list reload).
* **Import** (`ImportService`):
  * Header matched by column *name*; `amount`, `type`, `date`-or-`transaction_timestamp` and a
    category are required before any row is written.
  * Category/payee/group resolve **by name** (trimmed, case-insensitive) against the user's rows;
    an unknown name **skips its row and is reported** — nothing is created silently.
  * Every row passes `Validators` (amount > 0, ≤ 999,999,999; description ≤ 500) plus
    `type ∈ {Income, Expense}` and a `yyyy-MM-dd` date (a blank `date` derives from the timestamp's
    raw prefix via `TransactionTimestamp.day`, mirroring the save path).
  * Ids: blank or the sentinel literals `null`/`undefined` (§7) become fresh UUIDs; a provided id is
    kept, so re-importing an exported file upserts in place instead of duplicating.
  * Writes go through `TransactionService.save`: `sync_status = 1` (born dirty — the next push
    uploads the row), `deleted = 0`, `tid = 0`, denormalized names copied from the matched
    entities, blank optionals as SQL NULL.
  * Validation of all rows completes before any insert; the insert batch relies on the caller's
    `pool.write` transaction (§4's `SettingsService.resetLocalData` note), so a failure rolls back
    the whole batch.
* The codec (`Support/CSV.swift`) is RFC 4180: minimal quoting, `""` escapes, CRLF/LF row endings
  on decode (⚠️ a CRLF pair is **one** Swift `Character` — match `case "\r", "\r\n"`), BOM on
  encode and skipped on decode, embedded newlines preserved.

### 9.2 JSON backup

`ExportService.backupJSON` writes `{format: "jmoney-backup", version: 1, exported_at, user_id,
tables}` where `tables` holds all seven local tables for the user keyed by column name — including
`sync_status`/`tid`/`deleted` verbatim and soft-deleted rows, because a backup is a true snapshot.
SQL NULL becomes JSON `null` (distinct from `""`). **Restore is deliberately not implemented**:
resolving id collisions and cooperating with the next pull is a design task of its own (recorded
as an open item for a later phase).
