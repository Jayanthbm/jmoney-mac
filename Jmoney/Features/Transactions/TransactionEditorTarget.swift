import Foundation

/// Which transaction the editor sheet should open for.
///
/// `.new` is used by ⌘N / File > New Transaction and by empty-state actions;
/// `.edit` is used when a row (or the transaction context menu) asks to edit.
/// `.template` is the quick-transaction path (⌘⇧N / the bolt button): a new
/// transaction prefilled from a saved template, which is what the source's
/// `add-transaction?quickTransaction=<json>` route does.
enum TransactionEditorTarget: Identifiable, Equatable {
    case new
    case edit(Transaction)
    case template(QuickTransaction)

    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let transaction): return "edit-\(transaction.id)"
        case .template(let template): return "template-\(template.id)"
        }
    }

    var transaction: Transaction? {
        if case .edit(let transaction) = self { return transaction }
        return nil
    }

    var template: QuickTransaction? {
        if case .template(let template) = self { return template }
        return nil
    }
}
