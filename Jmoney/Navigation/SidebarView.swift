import SwiftUI

/// Sidebar listing every app area. The native equivalent of the React Native
/// app's bottom tabs plus its stack screens (MACOS_ARCHITECTURE.md §4).
struct SidebarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        List(selection: $appState.selectedSection) {
            Section("Finance") {
                sidebarRow(.dashboard)
                sidebarRow(.transactions)
                sidebarRow(.budgets)
                sidebarRow(.calendar)
                sidebarRow(.reports)
            }

            Section("Manage") {
                sidebarRow(.goals)
                sidebarRow(.categories)
                sidebarRow(.payees)
                sidebarRow(.groups)
                sidebarRow(.quickTransactions)
            }

            Section("General") {
                sidebarRow(.settings)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 220)
    }

    @ViewBuilder
    private func sidebarRow(_ section: AppSection) -> some View {
        Label(section.title, systemImage: section.systemImage)
            .tag(section)
    }
}
