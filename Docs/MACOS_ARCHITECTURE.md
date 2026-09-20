# Jmoney macOS — Architecture

> Populated after analyzing the React Native application's architecture and business behavior.
> Last updated: 2026-09-20 (Phase 1 analysis).

## Status

Analysis complete. This document describes the target architecture for the native macOS app.
Implementation begins at Phase 4 (App Shell).

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
│   ├── JmoneyApp.swift            # @main: WindowGroup + Settings scene + Commands
│   ├── AppCommands.swift          # ⌘N new transaction, ⌘R sync, ⌘F search, etc.
│   └── AppEnvironment.swift       # DB pool, services, session wiring (EnvironmentValues)
├── Navigation/
│   └── SidebarView.swift          # NavigationSplitView sidebar (tab equivalents)
├── Features/
│   ├── Auth/                      # Login window, session store, auth gate
│   ├── Dashboard/                 # Widgets: daily limit, remaining, pay day, top categories,
│   │                              #   month/year summaries, net worth, today's activity
│   ├── Transactions/              # List (sectioned), filters, search, stats, editor sheet
│   ├── Budgets/                   # List, month navigation, editor, drill-down
│   ├── Goals/
│   ├── Reports/                   # Index + 11 report pages + drill-down
│   ├── Calendar/
│   ├── Categories/  Payees/  Groups/  QuickTransactions/
│   └── Settings/                  # Appearance, reminders, lock, data mgmt, sync, account
├── Services/
│   ├── DatabaseService.swift      # GRDB pool, migrations, WAL
│   ├── SyncService.swift          # Full sync coordinator (mirror of syncService.ts)
│   ├── Sync/                      # Per-entity push/pull (transactions, budgets, goals,
│   │                              #   categories, payees, quick transactions, groups)
│   ├── SupabaseService.swift      # Client config, session persistence
│   ├── DashboardService.swift     # Metrics + daily-limit + payday calculations (pure, testable)
│   ├── TransactionService.swift   # Fetch/filter/stats (mirror transactionService.ts)
│   ├── BudgetService.swift  GoalService.swift  ReportService.swift  CalendarService.swift
│   ├── CategoryService.swift  PayeeService.swift  GroupService.swift  QuickTransactionService.swift
│   ├── NotificationService.swift  # Daily reminders
│   └── LocationService.swift      # GPS tagging
├── Models/                        # Transaction, Budget, Goal, Category, Payee,
│                                  #   QuickTransaction, TransactionGroup, ReportItem …
├── Stores/                        # @Observable app state: session, theme, toast/status
└── Support/                       # Formatters (₹/en-IN), validators, date utils, timestamp rules
JmoneyTests/                       # Business logic tests (calculations, validators, sync mappers)
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

- None blocking Phase 4. Data-layer decisions are recorded in DATA_ARCHITECTURE.md.
