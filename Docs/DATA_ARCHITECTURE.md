# Jmoney macOS — Data Architecture

> Populated after analyzing the React Native application's database, offline-first behavior,
> synchronization, and Supabase integration. Last updated: 2026-09-20 (Phase 1 analysis).

## Status

Analysis complete. Persistence decision made (§5). Implementation at Phase 5 (Data Layer).

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
| Daily limit | `(month.income − (month.expense − spentToday)) ÷ remainingDaysInMonth` (incl. today); floor 0; `remaining = max(0, limit − spentToday)`; `remaining% = remaining/(remaining+spent)×100` |
| Pay day | `daysInMonth − currentDay + 1` days remaining; next payday label `MMM 01` |
| Dashboard comparisons | Month MTD vs same-day previous month; year YTD vs same-day previous year |
| Budget spending | `SUM(amount)` of expenses in period where `category_id IN (budget's category JSON)` |
| Goal progress | `current_amount / goal_amount` |
| Report comparison | diff% = (current − previous)/previous × 100; previous matched by name/type; MTD-vs-MTD or YTD-vs-YTD for current period, full-vs-full otherwise; new items with no previous show +100% |
| Filtered total | Σ(income − expense) over the active transaction filter |
| Calendar day total | Σ(income − expense) for the selected date |
| Search | numbers → exact amount match; otherwise LIKE on description and amount-as-text |
| Sorting | Transactions: date desc then `transaction_timestamp` desc. Entities: `priority ASC, name ASC` default; user-selectable sorts per screen (see matrix) |
| Defaults | New expense → category "general"; new income → category "salary" (case-insensitive name match) |
| Validation | amount > 0 and ≤ 999,999,999; description ≤ 500 chars; category required; goal name required + current ≥ 0; budget name + ≥1 category + amount valid |
| Timestamps | `transaction_timestamp` = ISO local; `date` derived (`yyyy-MM-dd`); on push to Supabase the timezone suffix is stripped (`yyyy-MM-ddTHH:mm:ss.SSS`); on pull `date` is re-derived from the timestamp |
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

### 3.3 Pull (Supabase → local)
- **Meta entities** (goals, budgets, categories, payees, quick transactions, groups): *full replace* —
  delete all local rows for the user, then insert everything from Supabase with `sync_status = 0`.
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
- **Group deletion** hard-deletes only the group row; member transactions keep a dangling `group_id`
  (filters/reports tolerate this by joining names).
- **Category/payee deletion** is not exposed in the RN UI; do not add destructive paths without
  flagging them as new behavior.
- Sync-status fields must never be user-visible data; they are protocol internals.

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
  to avoid cross-device date drift.
