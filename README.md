# Jmoney for Mac

A native macOS port of the Jmoney personal finance tracker — offline-first, local SQLite,
Supabase sync. Built with SwiftUI, GRDB.swift and supabase-swift.

The React Native source app (at `../jayledger`) is the behavioral reference: every calculation,
sync quirk and sentinel value in the macOS app is ported to match it exactly. The parity contract
is documented row by row in [`Docs/MACOS_FEATURE_MATRIX.md`](Docs/MACOS_FEATURE_MATRIX.md).

**Status:** all 19 build phases complete · 634 tests green · version 3.0.0.

---

## Features

- **Offline-first ledger** — every read/write hits local SQLite (WAL) instantly; the UI never
  waits on the network. Supabase is the sync target, not the source of truth.
- **Dashboard** — daily spending limit, month remaining, pay-day countdown, top categories,
  month/year summaries vs the previous period, net worth.
- **Transactions** — day-grouped list with per-day nets, search, date-range and multi-select
  category/payee/group filters, stats popover, quick-transaction templates (⌘⇧N), location
  tagging (GPS capture, manual coordinates, Google Maps link).
- **Budgets & Goals** — progress tracking with the source's exact math, month navigation,
  sorting (including its stable-tie behavior), drill-downs.
- **Reports** — all 11 report types from the RN app, with previous-period comparisons,
  drill-downs and the living-costs configuration sheet.
- **Calendar** — month grid + per-day ledger, bounded navigation.
- **Management** — categories, payees, groups, quick-transaction templates with reorder,
  search, list/grid view modes and per-screen sync.
- **Sync** — full push/pull engine preserving the source's protocol (chunked incremental
  transaction pulls, full-replace entity pulls, born-dirty rows, per-entity last-sync
  timestamps, partial syncs after saves/deletes).
- **Security** — Supabase email/password auth, Keychain-backed sessions, Touch ID app lock,
  biometrics-only enable flow (as in the source).
- **Import / Export** (macOS-original) — CSV exports, a seven-table JSON backup, and a
  validated, name-mapped CSV transaction import with a per-row report.
- **Native Mac shell** — sidebar navigation, full keyboard set (⌘N, ⌘⇧N, ⌘F, ⌘R, ⌘E, ⇧⌘I,
  per-section New items), toolbar `+`/sync controls, status-bar toasts.

## Requirements

| Tool | Version | Notes |
| --- | --- | --- |
| macOS | 14 (Sonoma) or newer | deployment target |
| Xcode | 16 or newer | with the macOS SDK |
| [XcodeGen](https://github.com/yonaskolb/XcodeGen) | any recent | regenerates `Jmoney.xcodeproj` from `project.yml` |

Install XcodeGen if needed: `brew install xcodegen`

## Getting started

```bash
git clone <this-repo> jmoney-mac
cd jmoney-mac

# 1. (Optional) Point the app at your Supabase project.
#    Jmoney.xcconfig is committed as an empty template on purpose.
$EDITOR Jmoney.xcconfig

# 2. Generate the Xcode project (also required after adding/removing files).
xcodegen generate

# 3. Build and run.
xcodebuild -project Jmoney.xcodeproj -scheme Jmoney \
  -destination 'platform=macOS' build
open ~/Library/Developer/Xcode/DerivedData/Jmoney-*/Build/Products/Debug/Jmoney.app
```

Or simply `open Jmoney.xcodeproj` and press ⌘R.

### Supabase credentials

Fill in `Jmoney.xcconfig` locally (never commit real values):

```
JMONEY_SUPABASE_URL = https:/$()/your-project.supabase.co
JMONEY_SUPABASE_ANON_KEY = eyJhbGciOi...
```

> ⚠️ **The `https:/$()/` quirk is not a typo.** `//` starts a comment in an `.xcconfig`
> file, so a URL must be written with the empty `$()` between the slashes. Writing
> `https://host` silently truncates the value.

The anon key is public by design (it ships in every Supabase client), but it is still
configuration rather than code. The **service-role key must never go in this file** — the app
has no use for it and it bypasses RLS.

**Leaving both values empty is a supported state:** the app builds and runs with cloud sync
disabled, the auth gate explains why sign-in can't work, and sync attempts report the
configuration reason instead of pretending to succeed.

## Running the tests

```bash
xcodebuild -project Jmoney.xcodeproj -scheme Jmoney \
  -destination 'platform=macOS' test
```

634 tests: schema/defaults/indexes, record round-trips, timestamp rules, dashboard
calculations, formatters, budget/goal/report/calendar SQL and math, sync engine (including
every preserved quirk), CSV codec, export/import round trip, menu-audit conflict rules,
query-plan index proofs, 10,000-row scale correctness, and the location port.

## Building a release app

### 1. Release build (fastest)

```bash
xcodegen generate
xcodebuild -project Jmoney.xcodeproj -scheme Jmoney \
  -configuration Release -destination 'platform=macOS' build
```

The app lands at:

```
~/Library/Developer/Xcode/DerivedData/Jmoney-*/Build/Products/Release/Jmoney.app
```

Copy it wherever you like — it is self-contained.

### 2. Archive (the distributable artifact)

```bash
xcodebuild archive \
  -project Jmoney.xcodeproj \
  -scheme Jmoney \
  -configuration Release \
  -archivePath /tmp/Jmoney.xcarchive

# The installable app lives inside the archive:
cp -R /tmp/Jmoney.xcarchive/Products/Applications/Jmoney.app /Applications/
```

### 3. Verify the artifact (recommended)

```bash
APP=/Applications/Jmoney.app

# Signature: valid, ad-hoc (no team — correct for a local build).
codesign --verify "$APP" && echo OK

# No debug entitlement (get-task-allow must NOT appear).
codesign -d --entitlements :- "$APP" 2>/dev/null | grep -c get-task-allow   # → 0

# Identity: version, icon, category.
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
  -c "Print :CFBundleIconName" -c "Print :LSApplicationCategoryType" \
  "$APP/Contents/Info.plist"
```

What the release configuration guarantees:

- **No debug entitlements.** `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO` strips
  `com.apple.security.get-task-allow` from Release (Debug keeps it for lldb).
- **Zero warnings** in the app target.
- **App icon + credits + identity** baked in: `AppIcon.icns`, `CFBundleShortVersionString`
  3.0.0 (tracking the source app's `package.json`), Finance category, copyright, and the
  About-panel `Credits.html`.

### 4. Distributing beyond this machine

The current baseline is **ad-hoc signed** (`TeamIdentifier=not set`) — it runs on the machine
that built it and on others only with Gatekeeper's explicit override. To distribute normally
you need an Apple Developer team:

```bash
# In project.yml (or an xcconfig), set for Release:
#   DEVELOPMENT_TEAM = <YOUR_TEAM_ID>
#   CODE_SIGN_IDENTITY = "Developer ID Application"
#   CODE_SIGN_STYLE = Manual
#   ENABLE_HARDENED_RUNTIME = YES

xcodebuild archive -project Jmoney.xcodeproj -scheme Jmoney \
  -configuration Release -archivePath /tmp/Jmoney.xcarchive

xcodebuild -exportArchive -archivePath /tmp/Jmoney.xcarchive \
  -exportPath /tmp/export -exportOptionsPlist ExportOptions.plist

# Notarize + staple:
xcrun notarytool submit /tmp/export/Jmoney.app.zip --keychain-profile <profile> --wait
xcrun stapler staple /tmp/export/Jmoney.app
```

This is deliberately out of scope of the build itself; the packaging work it would need
(manual signing, hardened runtime, an `ExportOptions.plist`) is noted in
`Docs/AI_BUILD_PROGRESS.md` under Phase 19.

## Project layout

```
Jmoney/                  # App sources
├── App/                 # @main scene, menu commands, shell state
├── Navigation/          # Sidebar, root view, status bar
├── Features/            # One folder per screen area (Dashboard, Transactions, …)
├── Models/              # GRDB DTOs — column-faithful to the SQLite schema
├── Services/            # Business logic: per-entity services, sync engine, location
│   └── Sync/            # The seven entity sync modules
├── Stores/              # Session store
└── Support/             # Validators, formatters, preferences, pure rules
JmoneyTests/             # 634 tests (XCTest, in-memory GRDB fixtures)
Scripts/make_app_icon.swift  # Renders the ten-size app icon set
Docs/                    # The handoff documentation (see below)
project.yml              # XcodeGen manifest — the source of truth for the project
Jmoney.xcconfig          # Supabase credentials (empty template; local-only values)
Credits.html             # About-panel credits
```

## Documentation

The `Docs/` folder is the complete build record and handoff contract:

| Document | Contents |
| --- | --- |
| [`AI_BUILD_PROGRESS.md`](Docs/AI_BUILD_PROGRESS.md) | Phase-by-phase progress log, decisions, known issues, commit hashes — **read this first** |
| [`AI_BUILD_MASTER_PROMPT.md`](Docs/AI_BUILD_MASTER_PROMPT.md) | The rules every building agent follows |
| [`MACOS_FEATURE_MATRIX.md`](Docs/MACOS_FEATURE_MATRIX.md) | Every RN feature → macOS equivalent, row by row, with status |
| [`MACOS_ARCHITECTURE.md`](Docs/MACOS_ARCHITECTURE.md) | Module layout, tech decisions, interaction mapping |
| [`DATA_ARCHITECTURE.md`](Docs/DATA_ARCHITECTURE.md) | Schema, sync protocol, business rules, quirks, file-exchange contract |

## Implementation notes

- **Parity is a contract, not an aspiration.** Deliberate differences from the RN app
  (report window clamping, `parseFloat` tightening in manual coordinates, row-badge tap-to-sync)
  are documented in place in the matrix and data architecture docs — do not "fix" them silently.
- **The schema mirrors the RN app exactly**, including sentinel values (`'null'` ids, `''`
  names) and the born-dirty sync rule. Changing either breaks sync compatibility.
- **Regenerating the app icon:** edit `Scripts/make_app_icon.swift`, then
  `swift Scripts/make_app_icon.swift` and rebuild.
- **After adding or moving files:** run `xcodegen generate` before building.
