# Jmoney macOS — Feature Matrix

> Derived from a full source inspection of the React Native application at
> `/Users/jayanthbharadwajm/development/jayledger` (Expo SDK 58, Expo Router, expo-sqlite, Supabase).
> Last updated: 2026-09-21 (Phase 7 transactions implemented — see §1, §4 and §12 for updated rows).
>
> **Status legend:** `NOT STARTED` · `IN PROGRESS` · `COMPLETE` · `MACOS EQUIVALENT` · `BLOCKED`
> The *macOS* column records the planned/appropriate native equivalent. Implementation status is tracked
> per feature until the final parity audit (Phase 18) flips verified rows to `MACOS EQUIVALENT`.

---

## 1. App Shell & Navigation

| Feature | Existing App | macOS | Status | Notes |
| --- | --- | --- | --- | --- |
| Bottom tab navigation | `NativeTabs` with 5 tabs: Dashboard, Transactions, Budgets, Reports, Settings | `NavigationSplitView` sidebar listing all major areas | COMPLETE | Phase 4 shell: Finance / Manage / General sidebar sections host all 11 areas (tabs + stack-screen equivalents) |
| Root loader / redirect | `app/index.tsx` waits for auth session, redirects to login or dashboard | Window scene waits for DB init + session restore before showing content | IN PROGRESS | Gate exists (mock session); DB-init wait arrives with the Phase 5 data layer |
| Auth-gated routing | `RootLayoutNav` redirects unauthenticated users to `/(auth)/login` | Same gate at app-scene level; login window/sheet when signed out | IN PROGRESS | Phase 4: `AuthGateView` with mock sign-in; real Supabase + Keychain in Phase 14 |
| Modal transaction sheet | `add-transaction` transparent modal, slide-from-bottom | Sheet (`⌘N` new transaction) | COMPLETE | Phase 7: `TransactionEditorView` — type, date-time, category/payee/group, amount, description, product link, inline validation |
| Screen titles + last-synced subtitle | Header title with "Synced: Xm ago" | Toolbar title with subtitle; refresh toolbar button | IN PROGRESS | Phase 4: status bar shows "Last synced: …"; real timestamps with data layer/sync |
| iOS home-screen quick actions | `expo-quick-actions`: "New Transaction", "Quick Transaction" | Menu bar extra / Dock menu equivalents | IN PROGRESS | Phase 4: File > New Transaction (⌘N), File > Quick Transaction (⌘⇧N) |
| FAB (add) | Floating action buttons on Transactions/Budgets/Goals/etc. | Toolbar `+` button and ⌘N shortcuts | IN PROGRESS | Transactions has its toolbar `+` and empty-state action (Phase 7); the other areas add theirs with their phases |
| Toast notifications | `ToastContext` global toasts (success/error/info) | Native alerts / transient banners / status feedback in toolbar | IN PROGRESS | Phase 4: bottom status bar carries transient messages; error alerts arrive with real flows |
| Error boundaries | `DataErrorBoundary` wraps transaction list | Graceful error view with a Try Again action | COMPLETE | Transactions (Phase 7); the pattern carries to the remaining lists |
| Empty / loading states | Every list has empty placeholder + native loaders | Same, using native progress views | IN PROGRESS | Dashboard (Phase 6) and Transactions (Phase 7) have real empty/loading/error states; the other areas keep their Phase 4 placeholders |

## 2. Authentication & Security

| Feature | Existing App | macOS | Status | Notes |
| --- | --- | --- | --- | --- |
| Email/password sign-in | Supabase `signInWithPassword` on `/(auth)/login` | Login window with email/password; validate both non-empty | NOT STARTED | |
| Session persistence | Supabase session in AsyncStorage, autoRefreshToken | `supabase-swift` with Keychain-backed session storage | NOT STARTED | Session restore on launch |
| Session timeout guard | 7s timeout forces `loading=false` to avoid stuck splash | Same defensive timeout | NOT STARTED | |
| Sign out | Settings > Sign Out with confirmation (local data preserved) | Settings row + confirmation dialog | NOT STARTED | |
| Biometric app lock | `expo-local-authentication`; lock overlay re-appears on app foreground (`use_biometrics` pref) | Touch ID / password via `LAContext` when window activates; toggle in Settings | NOT STARTED | Hardware/enrollment check with error toast before enabling |
| Credential handling | Supabase URL + anon key hardcoded in `src/services/supabase.ts` | Config via build settings / Info.plist — never in source | NOT STARTED | Master prompt §15 forbids secrets in source. Anon key is public-by-design but still configured externally |

## 3. Dashboard

| Feature | Existing App | macOS | Status | Notes |
| --- | --- | --- | --- | --- |
| Daily spending limit card | `calculateDailyLimit`: (month income − expenses through yesterday) ÷ remaining days incl. today; progress bar of remaining % | Same formula in `DashboardService.calculateDailyLimit`; `DailyLimitCard` | COMPLETE | Formula normative in `DATA_ARCHITECTURE.md` §2; edge cases unit-tested (zero income, exhausted, overspend, last day) |
| Today's activity drill-down | `daily-limit-detail` ("Today's Activity"): total spent today + today's transaction list | Sheet: total spent today + today's transactions | COMPLETE | `TodaysActivityView`; total reduced from the on-screen rows exactly like RN. Row rendering is lightweight until Phase 7 builds the shared transaction row |
| Month remaining card | Income − expense for current month | `RemainingCard` with "% Spent" bar | COMPLETE | Title switches to "EXTRA SPENT" when negative; amount is `abs()` and the percent label is unclamped, both preserved from RN |
| Pay day countdown | Days remaining in month, "Next: MMM 01" label | `PayDayCard` with dot grid + ring | COMPLETE | `calculatePayDayInfo`; `MMM 01` label verified across month/year boundaries |
| Top categories | Top 3 expense categories for current month with amounts | `TopCategoriesCard` with bars | COMPLETE | Top-3 truncation and amount-descending order verified against SQL |
| This Month summary card | MTD income/expense vs same-day previous month | `SummaryCard`, click-through to the Monthly Summary report | COMPLETE | Trend `↑/↓n%` hidden when the previous period is 0; MTD-vs-MTD window (day clamped, Mar 31 → Feb 28) |
| This Year summary card | YTD income/expense vs same-day previous year | `SummaryCard`, click-through to the Yearly Summary report | COMPLETE | YTD-vs-YTD window |
| Net worth card | Σ(Income − Expense) over all non-deleted transactions | `NetWorthCard` | COMPLETE | `getNetWorth` port; sign dropped by the formatter, direction shown by colour (RN parity) |
| Sync status + manual refresh | Header refresh button, partial transaction sync, sync modal on first launch | Toolbar Refresh reloads metrics; ⌘R + sync progress modal | IN PROGRESS | Phase 6 added a real toolbar Refresh (reloads metrics from the local DB). Network sync and the first-launch modal remain Phase 14 |
| Cross-module refresh events | `DeviceEventEmitter 'module_refreshed'` for Dashboard/Transactions/Budgets | MACOS EQUIVALENT: metrics reload when the section appears + toolbar Refresh | COMPLETE | SwiftUI recreates the section on navigation, so no event bus is needed |
| Dashboard date-window derivation | date-fns `startOfMonth`/`endOfMonth`/`startOfYear`/`subMonths`/`subYears` | `DashboardService.dateWindows` + `subtracting` | COMPLETE | date-fns clamping replicated explicitly (Foundation would roll Mar 31 − 1 month into March, not February); 6 tests |

## 4. Transactions

| Feature | Existing App | macOS | Status | Notes |
| --- | --- | --- | --- | --- |
| Transaction list | FlashList, grouped by date, sticky date headers with per-day net totals | Native `List` sections with per-day headers and net totals; native selection + keyboard navigation | COMPLETE | `TransactionService.sections` ports `mapTransactionsToFlashList` (day groups newest-first, rows by timestamp newest-first). The FlashList *pinned* header overlay is not reproduced — native list section headers are used instead |
| Filtered net total chip | Shows Σ(Income−Expense) of current filter; color-coded positive/negative | Summary bar button above the list, colour-coded | COMPLETE | Same sign quirk preserved: `+` prefix when ≥ 0, no minus when negative (the currency helper drops the sign) |
| Search | Description LIKE or amount-as-text LIKE; pure numbers match exact amount | Toolbar search field (⌘F focuses it), 300 ms debounce | COMPLETE | Values are bound parameters, not interpolated; the numeric branch still replaces the LIKE entirely |
| Date range filter | Start/end date with quick presets (Today/This Week/This Month/This Year) | Popover: optional start/end pickers + the same four presets (week starts Monday) | COMPLETE | Either side can be "any date"; moving one bound past the other pushes it, matching the source |
| Multi-select category/payee/group filters | Multi-select sheets with search | Toolbar popovers with search + checkboxes | COMPLETE | Active counts show on the toolbar buttons |
| Active filter summary + Clear All | Text summary of active filters | Summary bar with the same text + Clear All | COMPLETE | `21 Sep - 30 Sep • 2 Cats • 1 Payee`, counts not names |
| Stats breakdown modal | 5-month income/expense trend for current filters (`getMonthlyFilteredStats`) | Popover from the total chip | COMPLETE | Last five calendar months, current first, signed net per month |
| Add transaction | Expense/Income segmented control, date+time picker, category/payee/group selector rows, amount, description, product link | Sheet (⌘N) with the same fields | COMPLETE | Defaults: "general" (expense) / "salary" (income), matched case-insensitively by name |
| Edit transaction | Same sheet pre-filled; type not editable on edit | Same sheet; the type control is hidden when editing | COMPLETE | Double-click a row, its context menu, or Return on the selection |
| Delete transaction | Soft delete (`deleted=1, sync_status=1`) + confirmation modal + background sync | Context menu / ⌫ on the selection + confirmation dialog | COMPLETE | Sync after delete arrives with Phase 14 |
| Quick transaction presets | `quick_transactions` templates prefill the add sheet (one-tap logging) | ⌘⇧N opens the preset picker | NOT STARTED | **Outstanding Phase 7 item** — the ⌘⇧N placeholder sheet still exists, but the preset→editor prefill is not built |
| Location tagging | Optional GPS capture (progressive accuracy w/ last-known fallback), manual lat/long edit, remove, open Google Maps | CoreLocation capture; map link; manual entry | NOT STARTED | **Outstanding Phase 7 item.** Edit shows saved coordinates read-only and preserves them on save; the row still opens Google Maps. Capture/editing not built |
| Per-card filter shortcuts | Long-press/actions: filter list by this payee/category | Context menu "Filter by Payee/Category" | COMPLETE | Disabled when the transaction has no payee |
| Category icon glyphs | Material icon name from `category_app_icon` | Neutral SF Symbol tinted by type | IN PROGRESS | **Outstanding:** the stored values are Material icon names; the mapping and picker belong with Phase 12. Incomes are green, expenses use the accent colour |
| Row sync indicator | Cloud badge on rows with `sync_status = 1`, tappable to sync | Omitted | NOT STARTED | Deliberately deferred to Phase 14: with no sync engine every row would be flagged, so the badge would be meaningless |
| Sync button + status | Partial transaction sync on demand, "Synced: Xm ago" | ⌘R / toolbar with the status bar | NOT STARTED | Phase 14 owns the sync engine; the status bar shows "Last synced" |
| Amount formatting | `₹` (INR, `en-IN`), 0 or 2 decimals | `AppFormat.currency` | MACOS EQUIVALENT | Indian digit grouping; sign dropped (source parity) — see §12 |

## 5. Budgets

| Feature | Existing App | macOS | Status | Notes |
| --- | --- | --- | --- | --- |
| Budget list | Budgets with amount, spent, progress bar per selected month | List/table with progress columns | NOT STARTED | |
| Month navigation | Prev/next month + year/month picker, "Back to Today" | Toolbar month picker + stepper | NOT STARTED | Bounded by min transaction date → current month end |
| Budget spending calc | Σ expenses in month for the budget's category set (`getBudgetSpending`) | Same SQL aggregate | NOT STARTED | `budget.categories` is a JSON array of category IDs. Sync quirks verified: push normalizes interval `Monthly`→`Month`; budgets with empty category arrays are silently skipped on push (stay dirty) |
| Sorting | Name / amount / spent / remaining, asc/desc | Sort menu | NOT STARTED | |
| Add/edit budget | Name, logo, amount, interval, start date, category multi-select (expense categories only) | Sheet with same fields | NOT STARTED | Validation: name required, ≥1 category, valid amount |
| Delete budget | Soft delete + confirmation | Same | NOT STARTED | |
| Drill-down | Budget → transaction list for its categories in month | Selection opens detail view | NOT STARTED | |
| Initial/auto sync | Syncs when list empty or never synced (`@initial_budget_sync_checked_`) | Same on first appearance | NOT STARTED | |

## 6. Goals

| Feature | Existing App | macOS | Status | Notes |
| --- | --- | --- | --- | --- |
| Goals list | Name, logo, goal vs current amount, progress % | List with progress bars | NOT STARTED | |
| Sorting | Name / progress / amount, asc/desc | Sort menu | NOT STARTED | |
| Add/edit goal | Name, logo, goal amount, current amount | Sheet | NOT STARTED | Validation: name required, target > 0, current ≥ 0 |
| Delete goal | Soft delete + confirmation | Same | NOT STARTED | |
| Sync | Entity-level push/pull, last-synced display | Same | NOT STARTED | |

## 7. Reports (11 report types)

| Feature | Existing App | macOS | Status | Notes |
| --- | --- | --- | --- | --- |
| Reports index | 11 report cards, grid/list view toggle (persisted `reports_view_mode`) | Source-list / collection with view toggle | NOT STARTED | |
| Monthly Summary | Income/expense for month vs previous period (MTD-vs-MTD or full month) | Report page | NOT STARTED | `reportType: monthlySummary` |
| Yearly Summary | Income/expense for year vs previous year (YTD-vs-YTD or full year) | Report page | NOT STARTED | |
| Transactions By Category | Per-category totals for month, with comparison % | Report page | NOT STARTED | |
| Transactions By Payee | Per-payee totals for month, with comparison % | Report page | NOT STARTED | |
| Transactions By Group | Per-group totals for month, with comparison % | Report page | NOT STARTED | |
| Transactions By Year | Per-category yearly totals with comparison | Report page | NOT STARTED | |
| Yearly Payees | Per-payee yearly totals with comparison | Report page | NOT STARTED | |
| Monthly Living Costs | Expenses restricted to `is_living_cost = 1` categories for month | Report page | NOT STARTED | |
| Subscription and Bills | Expenses in categories literally named 'Subscription' or 'Bills' | Report page | NOT STARTED | Preserves exact behavior |
| Payees Overview | All-time totals per payee (Expense or Income) | Report page | NOT STARTED | |
| Categories Overview | All-time totals per category (Expense or Income) | Report page | NOT STARTED | |
| Expense/Income type toggle | All reports support type switch | Segmented control | NOT STARTED | |
| Month/year selectors | `YearMonthSelector` on each report | Date pickers | NOT STARTED | |
| Previous-period comparison | diff% vs previous period (prev item matched by name/type) | Δ column / indicator | NOT STARTED | MTD vs MTD for current period; full-vs-full otherwise; `useFullPreviousPeriod` flag |
| Report drill-down | Tap report row → underlying transactions for that item/period | Selection opens detail view | NOT STARTED | `handleReportDrillDown` |
| Report search/sort | Search by name; sort by name/amount (priority overrides for groups) | Toolbar search + sort menu | NOT STARTED | |

## 8. Calendar

| Feature | Existing App | macOS | Status | Notes |
| --- | --- | --- | --- | --- |
| Month calendar grid | Selectable days, month bounds = min transaction date → end of current month | Native calendar grid or date picker + day list | NOT STARTED | |
| Day transactions | List of that day's transactions | Split view: calendar left, transactions right | NOT STARTED | |
| Daily net total | Σ(Income − Expense) for selected day | Summary header | NOT STARTED | |
| Month/year jump + prev/next | `YearMonthSelector`, bounded navigation | Same | NOT STARTED | |
| Goto Today | Button when a non-today date is selected | Toolbar button | NOT STARTED | |
| Collapsible calendar | Collapse grid to focus on list | Sidebar/segmented toggle | NOT STARTED | |

## 9. Categories / Payees / Groups / Quick Transactions

| Feature | Existing App | macOS | Status | Notes |
| --- | --- | --- | --- | --- |
| Categories CRUD | Add (name, type Expense/Income, app icon); list/grid view toggle; search; sort by name/priority | Management view with editor | NOT STARTED | Categories are add-only in RN UI (no edit/delete UI for categories). New categories auto-assign `priority = MAX+1`. Goals list has no priority; defaults to name ASC |
| Category living cost flag | `is_living_cost` toggle exists in DB layer (feeds Living Costs report) | Toggle in category editor | NOT STARTED | ⚠️ Verified quirk: the flag is **local-only** — excluded from category push and omitted from pull insert, so it resets to 0 after every full sync pull. Replicate for parity; flag to user as candidate fix |
| Category reorder | Explicit reorder mode with up/down arrows; priority persisted; pushed on Done | Drag-and-drop reorder (native) | NOT STARTED | |
| Category → transactions | Tap category → transactions filtered to it | Same navigation | NOT STARTED | |
| Payees CRUD | Add (name, logo); list/grid; search; sort; reorder; tap → filtered transactions | Management view with editor | NOT STARTED | |
| Transaction groups CRUD | Add/edit (name, description), delete (hard delete row), reorder, list/grid, search, sort | Management view with editor | NOT STARTED | Deletion does NOT reassign or delete member transactions |
| Quick transactions CRUD | Templates: name, type, amount, category, payee, description, product link; reorder; card/list view; delete (soft) | Management view with editor | NOT STARTED | `identifier` field reserved for home-screen quick actions |
| View mode persistence | Grid/list preference per screen in AsyncStorage | Persisted in UserDefaults | NOT STARTED | |

## 10. Settings

| Feature | Existing App | macOS | Status | Notes |
| --- | --- | --- | --- | --- |
| Theme selection | Light/Dark manual toggle, persisted `app_theme`, defaults to system | Native appearance following system + override; persisted | NOT STARTED | |
| Daily reminders | None / Morning 9AM / Evening 6PM / Night 9PM / Custom time; schedules daily local notification "Reminder 💰" | UserNotifications daily schedule; permission handling | NOT STARTED | |
| Biometrics toggle | Enable after verifying biometric; hardware/enrollment check | Touch ID toggle | NOT STARTED | |
| Haptics toggle | Persisted haptics setting gating `expo-haptics` triggers | Not meaningful on macOS → **MACOS EQUIVALENT: omit**; document | NOT STARTED | No haptic hardware on Macs |
| Manage data entries | Navigation to Goals, Categories, Payees, Groups, Quick Transactions | Sidebar items + Settings links | NOT STARTED | |
| Manual full sync | `runFullSync` all entities; shows "Last synced Xm ago" | Sync Now button + status (⌘R) | NOT STARTED | |
| Reset local data | `resetAppData`: transactional delete of transactions, budgets, goals, categories, payees, groups for user + clears prefs; confirmation; note: does **not** delete `quick_transactions` | Same behavior + confirmation dialog | NOT STARTED | Replicate exact behavior incl. quick-transactions quirk; flag for user decision later |
| Account email + sign out | Shows email; sign out w/ confirmation | Same | NOT STARTED | |

## 11. Sync, Offline & Data

| Feature | Existing App | macOS | Status | Notes |
| --- | --- | --- | --- | --- |
| Offline-first local DB | expo-sqlite (WAL), all reads/writes local | SQLite (GRDB) WAL | IN PROGRESS | Phase 5: WAL pool + v1 migration with the exact RN schema/indexes/defaults, column-faithful DTOs — 21 unit tests green. Query/read-write services land with each feature phase; push/pull below in Phase 14 |
| Push local changes | Entities with `sync_status = 1` upserted; deleted rows push remote delete then hard delete locally | Same protocol | NOT STARTED | |
| Pull: full replace | Goals, budgets, categories, payees, quick transactions, groups: delete-all-local then re-insert from Supabase | Same | NOT STARTED | Last-writer-wins by whole-table replace |
| Pull: incremental | Transactions: pull `tid > MAX(local tid)`, chunked (1000), joined category/payee/group names denormalized | Same | NOT STARTED | Server `tid` sequence is sync cursor |
| Force full transaction resync | Deletes all local transactions for user and re-pulls everything | Same ("Refresh" / repair) | NOT STARTED | |
| Sync coordination | `runFullSync` with per-entity steps, progress messages, re-entrancy guard, per-entity last-sync timestamps | Async sequence with same ordering + progress | NOT STARTED | |
| Connectivity check | NetInfo `isConnected && isInternetReachable` | NWPathMonitor | NOT STARTED | |
| Background auto-sync | After saves/deletes; dashboard focus check via `needsTransactionSync` (local max tid < remote max tid) | Same triggers on save/delete/appear | NOT STARTED | |
| Sync error handling | Errors logged, sync statuses left dirty for retry | Same + user-visible status | NOT STARTED | |

## 12. Platform / Other

| Feature | Existing App | macOS | Status | Notes |
| --- | --- | --- | --- | --- |
| Dark/light theme colors | iOS-system palette (see ThemeContext) | System materials + equivalent palette | NOT STARTED | |
| Keyboard toolbar / accessories | `NativeKeyboardToolbar` | Native key equivalents + focus handling | IN PROGRESS | ⌘N, ⌘⇧N, ⌘F (Edit > Find…), ⌘R (Data > Sync Now), ⌘, wired (Phase 4). Phase 7 added ⌫ delete on the transaction selection, Return/double-click to edit, and Return/Escape in the editor sheet |
| Keep awake | `expo-keep-awake` on add-transaction screen | Not applicable on macOS → omit | NOT STARTED | |
| CSV/JSON export | **Not implemented** (README claims it; no code found) | Planned as macOS-only enhancement (Phase 15) | NOT STARTED | Documented to avoid false parity claims |
| ajv dependency | In package.json but unused | N/A | NOT STARTED | No macOS counterpart needed |
| Data validation | Amount > 0, ≤ 999,999,999; description ≤ 500 chars; category required; goal/budget validators | Same rules in validation layer + unit tests | NOT STARTED | `utils/validators.ts` |
| Date/time handling | date-fns; `transaction_timestamp` ISO local format; `date` = `yyyy-MM-dd` derived; Supabase push strips timezone suffix | Foundation/Date + shared date utils; preserve timestamp semantics | IN PROGRESS | Phase 5: `Support/Timestamps.swift` ports `transactionTimestamp.ts` byte-compatibly (suffix conversion, prefix-day extraction, lowercase-t/z + no-colon offsets, UTC date-only quirk) — 11 fixed-timezone tests green |
| Currency | ₹ / en-IN | `AppFormat.currency` | MACOS EQUIVALENT | Indian digit grouping, 0 fraction digits for whole amounts and 2 otherwise, sign dropped — all verified by tests |

---

## Parity Audit Notes (Phase 1)

- Every user-facing screen in the RN app is inventoried above; nothing is silently dropped.
- Features that do not translate 1:1 (FABs, bottom tabs, haptics, keep-awake) have documented native equivalents or justified omissions.
- Export/backup (README claim) is absent in code; it is treated as a **new macOS feature** (Phase 15), not parity.
