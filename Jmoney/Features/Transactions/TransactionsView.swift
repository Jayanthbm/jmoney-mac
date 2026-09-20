import SwiftUI

/// Transactions placeholder — Phase 7 adds the date-sectioned list, filter
/// popovers, stats breakdown, and the editor. The search field is wired now so
/// ⌘F (Edit > Find) presents and focuses it from anywhere in the app.
struct TransactionsView: View {
    @Environment(AppState.self) private var appState

    @State private var searchText = ""
    @State private var isSearchPresented = false

    var body: some View {
        ContentUnavailableView {
            Label("No Transactions", systemImage: "tray")
        } description: {
            Text("Start tracking your finances by adding your first transaction.")
        } actions: {
            Button("New Transaction") {
                appState.showNewTransaction = true
            }
            .buttonStyle(.borderedProminent)
        }
        .navigationTitle("Transactions")
        .searchable(
            text: $searchText,
            isPresented: $isSearchPresented,
            prompt: "Search transactions"
        )
        .onChange(of: appState.searchRequestID) { _, _ in
            isSearchPresented = true
        }
    }
}
