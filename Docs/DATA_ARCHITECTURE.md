# Jmoney macOS — Data Architecture

> Populated after analyzing the React Native application's database, offline-first behavior,
> synchronization, and Supabase integration. Last updated: 2026-09-20 (Phase 5 data layer
> implemented: GRDB v1 migration + DTOs + timestamp rules, unit tested).

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
and the write path. Sync/push-pull logic itself lands in Phase 14.

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
| Goal progress | `current_amount / goal_amount` |
| Report comparison | diff% = (current − previous)/previous × 100; previous matched by name/type; MTD-vs-MTD or YTD-vs-YTD for current period, full-vs-full otherwise; new items with no previous show +100% |
| Filtered total | Σ(income − expense) over the active transaction filter |
| Calendar day total | Σ(income − expense) for the selected date |
| Search | numbers → exact amount match; otherwise LIKE on description and amount-as-text. The numeric form is `^-?\d+(\.\d+)?$`, and when it matches the LIKE is **not** run at all (so `5` does not match a description containing "5"). Exception: `getMonthlyFilteredStats` never takes the numeric branch — its search is always the LIKE, so there `50` *does* match "500 note electricity" |
| Sorting | Transactions: date desc then `transaction_timestamp` desc. Entities: `priority ASC, name ASC` default; user-selectable sorts per screen (see matrix) |
| Defaults | New expense → category "general"; new income → category "salary" (case-insensitive name match) |
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
  `@quick_transaction_view_mode_`).
- **`is_living_cost` is local-only**: the category push strips it and the pull insert omits it, so
  the flag **resets to `0` after every full pull** — the Living Costs report silently loses its
  selection after sync. Replicate for parity, but flag to the user as a candidate fix.
- **Priority auto-assignment**: new categories/payees/groups/quick-transactions get
  `priority = MAX(priority) + 1` when created without an explicit priority.
- **Group deletion** hard-deletes only the group row; member transactions keep a dangling `group_id`
  (filters/reports tolerate this by joining names).
- **Category/payee deletion** is not exposed in the RN UI; do not add destructive paths without
  flagging them as new behavior.
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

## 8. Verification Record (second agent, 2026-09-20)

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
