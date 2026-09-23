import SwiftUI

/// Menu bar commands for the app shell.
///
/// Shortcuts follow MACOS_ARCHITECTURE.md §4: ⌘N new transaction, ⌘⇧N quick
/// transaction, ⌘F find, ⌘R sync. ⌘, is provided by the Settings scene.
struct AppCommands: Commands {
    let appState: AppState

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
        }

        CommandGroup(after: .newItem) {
            Button("Export…") {
                appState.showExportSheet = true
            }
            .keyboardShortcut("e", modifiers: .command)

            Button("Import Transactions…") {
                appState.showImportSheet = true
            }
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
        }
    }
}
