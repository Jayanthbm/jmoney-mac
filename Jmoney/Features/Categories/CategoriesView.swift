import SwiftUI

/// Categories placeholder — Phase 12 adds category management: add (name, type,
/// app icon), list/grid toggle, search, sorting, drag-and-drop reorder, the
/// living-cost toggle, and drill-down to transactions.
struct CategoriesView: View {
    var body: some View {
        ContentUnavailableView {
            Label("No Categories", systemImage: "square.grid.2x2")
        } description: {
            Text("Categories organize your transactions into expense and income types.")
        }
        .navigationTitle("Categories")
    }
}
