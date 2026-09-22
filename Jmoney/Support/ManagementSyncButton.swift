import SwiftUI

/// The management screens' toolbar sync button — the native reading of the
/// `MaterialIcons refresh` button in the RN headers of budgets, goals,
/// categories, payees, groups and quick transactions.
///
/// The label is the entity's name, so the status bar's confirmation reads like
/// the source's own toasts ("Budgets synced successfully"). While the request is
/// in flight the icon swaps to a progress view, as the source swaps in
/// `NativeLoadingIndicator`.
struct ManagementSyncButton: View {
    let entity: SyncEntity
    /// The request to raise; `RootView` owns the runner.
    let action: () -> Void
    /// True while a sync is under way (`AppState.isSyncing`).
    let isSyncing: Bool

    var body: some View {
        if isSyncing {
            ProgressView()
                .controlSize(.small)
                .help("Syncing \(entity.displayName)…")
                .accessibilityLabel("Syncing \(entity.displayName)")
        } else {
            Button(action: action) {
                Label(
                    "Sync \(entity.displayName)",
                    systemImage: "arrow.triangle.2.circlepath"
                )
            }
            .help("Sync \(entity.displayName)")
        }
    }
}
