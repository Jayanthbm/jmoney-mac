import SwiftUI

/// Menu bar commands for the app shell.
///
/// Shortcuts follow MACOS_ARCHITECTURE.md §4 and the Phase 16 audit: ⌘N new
/// transaction, ⌘⇧N quick transaction, ⌘F find, ⌘R sync, ⌘E export, the ⇧⌘
/// new-item series, ⇧⌘I import. ⌘, is provided by the Settings scene.
///
/// `menuAuditTable` is the single source of truth for the shortcut set: the
/// body builds from it, and `CommandsTests` runs the standard-macOS conflict
/// rules against it (the three plain-⌘ re-uses each carry their safety reason
/// in the test). Add a shortcut without clearing the audit and the suite fails.
struct AppCommands: Commands {
    let appState: AppState

    /// One row per **shortcut-bearing** menu item: the exact menu string plus
    /// the key/modifiers SwiftUI binds. (Sync Transactions, Sync This Section
    /// and Help are registered too but deliberately carry no equivalents.) The
    /// body and this table must stay in step — the audit tests enforce it.
    static let menuAuditTable: [(title: String, key: KeyEquivalent, modifiers: EventModifiers)] = [
        ("New Transaction…", "n", .command),
        ("Quick Transaction…", "n", [.command, .shift]),
        ("New Budget…", "b", [.command, .shift]),
        ("New Goal…", "g", [.command, .shift]),
        ("New Category…", "c", [.command, .shift]),
        ("New Payee…", "p", [.command, .shift]),
        ("New Group…", "t", [.command, .shift]),
        ("New Template…", "m", [.command, .shift]),
        ("Export…", "e", .command),
        ("Import Transactions…", "i", [.command, .shift]),
        ("Find…", "f", .command),
        ("Sync Now", "r", .command),
    ]

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Transaction…") {
                appState.beginNewTransaction()
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("Quick Transaction…") {
                appState.showQuickTransactionPicker = true
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Divider()

            Button("New Budget…") {
                appState.selectedSection = .budgets
                appState.requestSectionEditor()
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])

            Button("New Goal…") {
                appState.selectedSection = .goals
                appState.requestSectionEditor()
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])

            Divider()

            Button("New Category…") {
                appState.selectedSection = .categories
                appState.requestSectionEditor()
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])

            Button("New Payee…") {
                appState.selectedSection = .payees
                appState.requestSectionEditor()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])

            Button("New Group…") {
                appState.selectedSection = .groups
                appState.requestSectionEditor()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])

            Button("New Template…") {
                appState.selectedSection = .quickTransactions
                appState.requestSectionEditor()
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
        }

        CommandGroup(after: .newItem) {
            Button("Export…") {
                appState.showExportSheet = true
            }
            .keyboardShortcut("e", modifiers: .command)

            Button("Import Transactions…") {
                appState.showImportSheet = true
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
        }

        // The default SwiftUI Edit menu has no Find submenu (that comes from
        // TextEditingCommands, which this app does not include), so placing
        // Find here owns the ⌘F shortcut without conflicts.
        CommandGroup(after: .pasteboard) {
            Button("Find…") {
                appState.requestSearchFocus()
            }
            .keyboardShortcut("f", modifiers: .command)
        }

        CommandMenu("Data") {
            Button("Sync Now") {
                appState.requestSync()
            }
            .keyboardShortcut("r", modifiers: .command)

            Divider()

            Button("Sync Transactions") {
                appState.selectedSection = .transactions
                appState.requestTransactionSync(isPartial: true)
            }

            // The frontmost management screen's own entity sync — the same
            // request its toolbar button raises.
            Button("Sync This Section") {
                appState.requestSectionSync()
            }
        }

        CommandGroup(replacing: .help) {
            Button("Jmoney Help") {
                appState.statusMessage = "Jmoney — your finances, offline-first. ⌘N new transaction, ⌘⇧N quick transaction, ⇧⌘B/G/C/P/T/M new budget/goal/category/payee/group/template, ⌘F find, ⌘R sync, ⌘E export, ⇧⌘I import."
            }
        }
    }
}
