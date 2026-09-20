import SwiftUI

/// Groups placeholder — Phase 12 adds transaction-group management: add/edit,
/// hard delete (member transactions keep their group reference, matching the
/// React Native app), reorder, list/grid toggle, and search.
struct GroupsView: View {
    var body: some View {
        ContentUnavailableView {
            Label("No Groups", systemImage: "folder")
        } description: {
            Text("Groups bundle related transactions for reporting.")
        }
        .navigationTitle("Groups")
    }
}
