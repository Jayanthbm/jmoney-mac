#!/usr/bin/env bash
# Jmoney — reset and rebuild the Debug configuration.
#
# Wipes every piece of local state the app can accumulate, then does a fresh
# debug build. Use it when the app should start as a true first run: schema
# migrating from scratch, signed out, default preferences.
#
# Usage:
#   Scripts/reset_debug.sh            # reset + rebuild, then print the launch hint
#   Scripts/reset_debug.sh --launch   # reset + rebuild + launch the fresh build
#   Scripts/reset_debug.sh --keep-data  # rebuild only, keep local data/keychain/prefs
#
# What gets deleted:
#   ~/Library/Developer/Xcode/DerivedData/Jmoney-*     (debug AND release products)
#   ~/Library/Application Support/Jmoney               (SQLite db + WAL sidecars)
#   Keychain items under service com.jayanth.jmoney.auth (sign-in session)
#   defaults domain com.jayanth.jmoney                 (prefs: theme, view modes,
#                                                       reminders, sync timestamps)

set -euo pipefail

LAUNCH=false
KEEP_DATA=false
for arg in "$@"; do
    case "$arg" in
        --launch) LAUNCH=true ;;
        --keep-data) KEEP_DATA=true ;;
        *)
            echo "Unknown argument: $arg" >&2
            echo "Usage: Scripts/reset_debug.sh [--launch] [--keep-data]" >&2
            exit 1
            ;;
    esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_ID="com.jayanth.jmoney"
KEYCHAIN_SERVICE="com.jayanth.jmoney.auth"
APP_SUPPORT="$HOME/Library/Application Support/Jmoney"
DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData"

# 0) Quit the app if it is running (graceful first, then force), and wait until
#    it is actually gone — deleting DerivedData under a live process fails with
#    "Directory not empty".
osascript -e 'tell application "Jmoney" to quit' >/dev/null 2>&1 || true
pkill -f "Jmoney.app/Contents/MacOS/Jmoney" 2>/dev/null || true
for _ in $(seq 1 20); do
    pgrep -f "Jmoney.app/Contents/MacOS/Jmoney" >/dev/null 2>&1 || break
    sleep 0.5
done
pkill -9 -f "Jmoney.app/Contents/MacOS/Jmoney" 2>/dev/null || true
sleep 1

if [[ "$KEEP_DATA" == true ]]; then
    echo "→ --keep-data: skipping data/keychain/prefs cleanup"
else
    # 1) All build products (debug and release alike — DerivedData holds both).
    #    Retried: Xcode's background indexing can hold a file open for a moment
    #    after the app dies.
    echo "→ Deleting DerivedData (debug + release build products)"
    for attempt in 1 2 3; do
        if rm -rf "$DERIVED_DATA"/Jmoney-* 2>/dev/null; then
            break
        fi
        echo "    retry $attempt (a process is still holding build files)"
        sleep 2
    done
    rm -rf "$DERIVED_DATA"/Jmoney-*

    # 2) The local database (WAL pool: db + -shm + -wal sidecars).
    echo "→ Deleting local data ($APP_SUPPORT)"
    rm -rf "$APP_SUPPORT"

    # 3) The Keychain sign-in session. `security delete-generic-password` removes
    #    one item per call, so loop until the service has nothing left.
    echo "→ Clearing Keychain session ($KEYCHAIN_SERVICE)"
    while security delete-generic-password -s "$KEYCHAIN_SERVICE" >/dev/null 2>&1; do
        :
    done

    # 4) Preferences (theme, view modes, reminders, sync timestamps).
    echo "→ Clearing preferences ($BUNDLE_ID)"
    defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
fi

# 5) Regenerate the project (cheap, and covers file additions/removals) and build.
echo "→ Generating project"
cd "$REPO_ROOT"
xcodegen generate

echo "→ Building Debug"
xcodebuild -project Jmoney.xcodeproj -scheme Jmoney \
    -destination 'platform=macOS' clean build 2>&1 |
    { grep -E "error:|warning: .*jmoney-mac/Jmoney/|BUILD (SUCCEEDED|FAILED)" || true; }

# 6) Point at the fresh build.
APP=$(ls -d "$DERIVED_DATA"/Jmoney-*/Build/Products/Debug/Jmoney.app 2>/dev/null | head -1)
if [[ -z "$APP" ]]; then
    echo "✗ Build product not found — the build likely failed above." >&2
    exit 1
fi

echo "✓ Fresh debug build at:"
echo "    $APP"

if [[ "$LAUNCH" == true ]]; then
    echo "→ Launching"
    open "$APP"
else
    echo "  Launch it with:"
    echo "    open \"$APP\""
    echo "  (or re-run with --launch)"
fi
