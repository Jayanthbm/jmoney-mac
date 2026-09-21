import Foundation

/// Which budget the editor sheet should open for.
///
/// `.new` comes from the toolbar's New Budget button and the empty-state action;
/// `.edit` from a row's Edit command.
enum BudgetEditorTarget: Identifiable, Equatable {
    case new
    case edit(Budget)

    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let budget): return "edit-\(budget.id)"
        }
    }

    var budget: Budget? {
        if case .edit(let budget) = self { return budget }
        return nil
    }
}
