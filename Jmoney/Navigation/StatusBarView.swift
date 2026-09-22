import SwiftUI

/// Finder-style status bar pinned to the bottom of the window. Carries sync
/// status and transient feedback; the native replacement for the React Native
/// app's toasts and its "Synced: Xm ago" header subtitle.
///
/// While a sync is running it shows the engine's own progress step, which is how
/// the source's `DashboardSyncModal` progress text survives on macOS: the modal
/// itself is not reproduced, because the shell already has a persistent status
/// surface and a modal would block the whole window for a background job.
struct StatusBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(SyncService.self) private var syncService

    private var message: String {
        if appState.isSyncing {
            return syncService.lastProgress?.message ?? "Syncing…"
        }
        return appState.statusMessage ?? "Ready"
    }

    var body: some View {
        HStack(spacing: 8) {
            if appState.isSyncing {
                ProgressView()
                    .controlSize(.mini)
            }

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(message)

            Spacer()

            Text("Last synced: \(appState.lastSyncText)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .combine)
    }
}
