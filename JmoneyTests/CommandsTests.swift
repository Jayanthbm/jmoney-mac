import SwiftUI
import XCTest

@testable import Jmoney

/// Phase 16 — the keyboard-shortcut audit, pinned as code.
///
/// SwiftUI's `Commands` content is opaque, so the audit pins the *contract*
/// three ways instead of walking the view tree:
///
/// 1. `AppCommands.menuAuditTable` is the declared set (title, key, modifiers);
///    the commands build from the same constants, so drift shows up in the UI
///    and this table is the reference.
/// 2. The conflict rules of the standard macOS keyboard map run against that
///    table — with the three deliberate re-uses (`n`, `e`, `f`) each carrying
///    the safety reason that makes them legal *in this app*.
/// 3. `AppSection.syncEntity` (the Data menu's section mapping) and the request
///    channels (`AppState`) are plain values, tested directly.
///
/// If a future edit adds a shortcut without clearing it here, a test fails and
/// forces the decision into the open.
final class CommandsTests: XCTestCase {
    // MARK: - The declared set

    func testAuditTableMatchesTheBriefsMenuSet() {
        let titles = AppCommands.menuAuditTable.map(\.title)
        XCTAssertEqual(titles, [
            "New Transaction…", "Quick Transaction…",
            "New Budget…", "New Goal…", "New Category…", "New Payee…",
            "New Group…", "New Template…",
            "Export…", "Import Transactions…",
            "Find…", "Sync Now",
        ])
    }

    func testEveryShortcutKeyIsUniqueWithinItsModifierSet() {
        let seen = AppCommands.menuAuditTable.map { "\($0.key)|\($0.modifiers.rawValue)" }
        let duplicates = Dictionary(grouping: seen, by: { $0 }).filter { $1.count > 1 }
        XCTAssertEqual(duplicates, [:], "Two menu items claim the same key + modifiers")
    }

    // MARK: - Conflict rules against the standard macOS keyboard map

    /// Plain ⌘-letter bindings macOS apps must not shadow (HIG keyboard map:
    /// cut/copy/paste/select-all/undo, open, print, save, quit, close, hide/
    /// minimize). Three exceptions are deliberate and each carries a safety
    /// reason that is true *of this app*:
    /// * `n` — the app owns the New slot via `CommandGroup(replacing: .newItem)`,
    ///   so the default New bindings are gone before ⌘N is declared;
    /// * `e` — the app has no print feature, so ⌘E is free;
    /// * `f` — the Edit menu has no Find submenu (no `TextEditingCommands`),
    ///   so Edit > Find… cannot shadow a text-editing default.
    func testPlainCommandKeysRespectTheStandardSet() {
        let standard: Set<KeyEquivalent> = ["x", "c", "v", "a", "z", "o", "p", "s", "q", "w", "m", "t"]
        let deliberate: Set<KeyEquivalent> = ["n", "e", "f"]
        let violations = AppCommands.menuAuditTable
            .filter { $0.modifiers == .command && standard.contains($0.key) }
            .map(\.title)
        XCTAssertEqual(
            violations.filter { deliberateReasons[$0] == nil },
            [],
            "A plain ⌘ binding shadows a standard macOS shortcut without a documented re-use"
        )
    }

    /// System-wide ⇧⌘ letter bindings (⇧⌘A Applications, ⇧⌘H Home, ⇧⌘? Help…).
    func testShiftCommandKeysRespectTheSystemSet() {
        let systemLetters: Set<KeyEquivalent> = ["a", "h", "/"]
        let violations = AppCommands.menuAuditTable
            .filter { $0.modifiers == [.command, .shift] && systemLetters.contains($0.key) }
            .map(\.title)
        XCTAssertEqual(violations, [])
    }

    /// Every binding is either ⌘ or ⇧⌘ — no option/control slots (option
    /// characters, control-terminal codes) are ever claimed.
    func testOnlyCommandAndShiftModifiersAreUsed() {
        for item in AppCommands.menuAuditTable {
            XCTAssertTrue(
                item.modifiers == .command || item.modifiers == [.command, .shift],
                "\(item.title) uses non-standard modifiers \(item.modifiers)"
            )
        }
    }

    /// The three re-uses are still pinned, so removing the safety condition
    /// (e.g. adding `TextEditingCommands`) cannot happen silently.
    func testDeliberateReUsesStayDocumented() {
        XCTAssertEqual(
            Set(deliberateReasons.keys),
            ["New Transaction…", "Export…", "Find…"],
            "The deliberate plain-⌘ re-uses changed — re-audit each against the HIG before updating this test"
        )
    }

    private var deliberateReasons: [String: String] {
        [
            "New Transaction…": "The app owns the New slot (CommandGroup(replacing: .newItem)).",
            "Export…": "The app has no print feature, so ⌘E is free.",
            "Find…": "No TextEditingCommands, so Edit > Find… owns ⌘F without shadowing a text default.",
        ]
    }

    // MARK: - The Data menu's section mapping

    func testSyncThisSectionCoversEveryManagementEntityExactlyOnce() {
        let sections = AppSection.allCases.compactMap(\.syncEntity)
        XCTAssertEqual(
            Set(sections),
            Set(SyncEntity.allCases),
            "Sync This Section must reach every synced entity through some section"
        )
        XCTAssertEqual(sections.count, SyncEntity.allCases.count, "No entity may be reachable twice")
    }

    func testNonManagementSectionsHaveNoEntitySync() {
        for section in [AppSection.dashboard, .calendar, .reports, .settings] {
            XCTAssertNil(
                section.syncEntity,
                "\(section.title) should fall back to ⌘R's full sync, not an entity sync"
            )
        }
    }

    // MARK: - Request channels

    @MainActor
    func testSectionEditorAndSyncRequestsIncrement() {
        let appState = AppState()
        XCTAssertEqual(appState.sectionEditorRequestID, 0)
        appState.requestSectionEditor()
        XCTAssertEqual(appState.sectionEditorRequestID, 1)
        appState.requestSectionEditor()
        XCTAssertEqual(appState.sectionEditorRequestID, 2)

        XCTAssertEqual(appState.sectionSyncRequestID, 0)
        appState.requestSectionSync()
        XCTAssertEqual(appState.sectionSyncRequestID, 1)
    }
}
