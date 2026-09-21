import Foundation

/// Which goal the editor sheet should open for.
///
/// `.new` comes from the toolbar's Add New Goal button and the empty-state action;
/// `.edit` from a row, whose RN equivalent opens the editor on a tap.
enum GoalEditorTarget: Identifiable, Equatable {
    case new
    case edit(Goal)

    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let goal): return "edit-\(goal.id)"
        }
    }

    var goal: Goal? {
        if case .edit(let goal) = self { return goal }
        return nil
    }
}
