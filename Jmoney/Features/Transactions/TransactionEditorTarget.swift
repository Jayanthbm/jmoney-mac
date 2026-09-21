import Foundation

/// Which transaction the editor sheet should open for.
///
/// `.new` is used by ⌘N / File > New Transaction and by empty-state actions;
/// `.edit` is used when a row (or the transaction context menu) asks to edit.
enum TransactionEditorTarget: Identifiable, Equatable {
    case new
    case edit(Transaction)

    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let transaction): return "edit-\(transaction.id)"
        }
    }

    var transaction: Transaction? {
        if case .edit(let transaction) = self { return transaction }
        return nil
    }
}
