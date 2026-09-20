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

# Phase Status

| Phase | Description                         | Status      |
| ----- | ----------------------------------- | ----------- |
| 0     | Project initialization              | COMPLETE    |
| 1     | Analyze React Native application    | COMPLETE    |
| 2     | Feature inventory                   | COMPLETE    |
| 3     | macOS architecture                  | COMPLETE    |
| 4     | Native app shell                    | NOT STARTED |
| 5     | Data layer                          | NOT STARTED |
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

**Phase:** 4 — Native App Shell

Build the SwiftUI app skeleton: `NavigationSplitView` sidebar with all areas, empty feature views,
`WindowGroup` + `Settings` scene, `Commands` (⌘N new transaction, ⌘R sync, ⌘F search), app
environment wiring, and the auth gate placeholder. Do not start the data layer until the shell
compiles and navigates.

Recommended order after that: 5 (Data layer + GRDB schema/migrations) → 14-in-part (Supabase client +
session store, so sync can be built) → 6 (Dashboard) → 7 (Transactions) → remaining features.

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

---

# Known Issues

* None in the macOS project. (RN-side observations that constrain the port are listed in
  `DATA_ARCHITECTURE.md` §7 — they are parity constraints, not defects to fix silently.)

---

# Next Agent Instructions

Start with Phase 4 (Native App Shell) using `MACOS_ARCHITECTURE.md` §3 as the module layout:

1. Add dependencies to `project.yml` when needed (GRDB, supabase-swift at Phase 5; shell needs none).
2. Build the sidebar shell with placeholder views for: Dashboard, Transactions, Budgets, Reports,
   Calendar, Goals, Categories, Payees, Groups, Quick Transactions, Settings.
3. Add `Commands` for ⌘N (new transaction), ⌘R (sync), ⌘F (search) and a `Settings` scene (⌘,).
4. Wire an app environment holder for future services (DB, session, sync).
5. Keep every screen's empty state present from the start.
6. Run `xcodegen generate` (if project.yml changed) and the build command; do not commit a red build.
7. Then proceed to Phase 5 per `DATA_ARCHITECTURE.md` §5, and Phase 6+ per the matrix.

Do not re-analyze the RN app from scratch — this file plus the three docs are the analysis record.

### Phase 1 Commit

`6b1f36d` — 2026-09-20 — "phase: analyze existing application" (recorded in a follow-up docs commit;
the hash refers to the phase commit containing the full documentation update).
