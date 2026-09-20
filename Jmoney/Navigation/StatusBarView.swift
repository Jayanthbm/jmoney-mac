import SwiftUI

/// Finder-style status bar pinned to the bottom of the window. Carries sync
/// status and transient feedback; the native replacement for the React Native
/// app's toasts and its "Synced: Xm ago" header subtitle.
struct StatusBarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 8) {
            if appState.isSyncing {
                ProgressView()
                    .controlSize(.mini)
            }

            Text(appState.statusMessage ?? "Ready")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(appState.statusMessage ?? "Ready")

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
