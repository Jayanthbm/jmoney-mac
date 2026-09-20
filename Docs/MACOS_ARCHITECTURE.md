# Jmoney macOS — Architecture

> Populated after analyzing the React Native application's architecture and business behavior.
> Last updated: 2026-09-20 (Phase 4 app shell implemented).

## Status

Analysis complete (Phase 1, re-verified — see DATA_ARCHITECTURE.md §8). **App shell implemented
(Phase 4)**: NavigationSplitView sidebar, all 11 feature views with empty states, menu commands
(⌘N/⌘⇧N/⌘F/⌘R), Settings scene (⌘,), status bar, mock-session auth gate. Next: Phase 5 (data layer).

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
│   ├── AppCommands.swift          # ⌘N/⌘⇧N new+quick transaction, ⌘F find, Data menu ⌘R  [Phase 4 ✓]
│   └── AppState.swift             # @Observable shell state: selection, sheets, search,
│                                  #   status bar (AppEnvironment-style service wiring lands in Phase 5)
├── Navigation/
│   ├── AppSection.swift           # Sidebar destinations enum  [Phase 4 ✓]
│   ├── SidebarView.swift          # NavigationSplitView sidebar  [Phase 4 ✓]
│   ├── RootView.swift             # Auth gate + split view + sheets + detail routing  [Phase 4 ✓]
│   └── StatusBarView.swift        # Bottom status bar (sync status, messages)  [Phase 4 ✓]
├── Features/
│   ├── Auth/                      # AuthGateView placeholder (mock session)  [Phase 4 ✓; real auth Phase 14]
│   ├── Dashboard/                 # Widgets: daily limit, remaining, pay day, top categories,
│   │                              #   month/year summaries, net worth, today's activity   [Phase 6]
│   ├── Transactions/              # List (sectioned), filters, search, stats, editor sheet  [Phase 7]
│   ├── Budgets/                   # List, month navigation, editor, drill-down   [Phase 8]
│   ├── Goals/                     # [Phase 9]
│   ├── Reports/                   # Index + 11 report pages + drill-down   [Phase 10]
│   ├── Calendar/                  # [Phase 11]
│   ├── Categories/  Payees/  Groups/  QuickTransactions/   # [Phase 12]
│   └── Settings/                  # Pane + ⌘, scene views   [Phase 13]
├── Services/
│   ├── DatabaseService.swift      # GRDB pool, migrations, WAL   [Phase 5]
│   ├── SyncService.swift          # Full sync coordinator (mirror of syncService.ts)   [Phase 14]
│   ├── Sync/                      # Per-entity push/pull (transactions, budgets, goals,
│   │                              #   categories, payees, quick transactions, groups)   [Phase 14]
│   ├── SupabaseService.swift      # Client config, session persistence   [Phase 14]
│   ├── DashboardService.swift     # Metrics + daily-limit + payday calculations (pure, testable)   [Phase 6]
│   ├── TransactionService.swift   # Fetch/filter/stats (mirror transactionService.ts)   [Phase 7]
│   ├── BudgetService.swift  GoalService.swift  ReportService.swift  CalendarService.swift
│   ├── CategoryService.swift  PayeeService.swift  GroupService.swift  QuickTransactionService.swift
│   ├── NotificationService.swift  # Daily reminders   [Phase 13]
│   └── LocationService.swift      # GPS tagging   [Phase 7]
├── Models/                        # Transaction, Budget, Goal, Category, Payee,
│                                  #   QuickTransaction, TransactionGroup, ReportItem …   [Phase 5]
├── Stores/
│   └── SessionStore.swift         # @Observable session (mock now; Supabase+Keychain Phase 14)  [Phase 4 ✓]
└── Support/
    └── Formatters.swift           # Relative time now; ₹/en-IN + date utils with data layer  [Phase 4 ✓]
JmoneyTests/                       # Business logic tests (calculations, validators, sync mappers)  [Phase 5+]
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

- None blocking Phase 5. Data-layer decisions are recorded in DATA_ARCHITECTURE.md.
- Shell notes: ⌘F is owned by Edit > Find… (no TextEditingCommands are included, so there is no
  conflict); Find currently presents the search field on the Transactions view only. ⌘R lives in a
  custom Data menu and reports "not connected" until the sync engine exists. The auth gate uses a
  mock session; sign-out is added with real auth (Phase 14).
