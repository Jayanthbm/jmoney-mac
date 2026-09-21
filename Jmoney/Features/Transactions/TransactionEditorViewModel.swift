import Foundation
import GRDB
import Observation

/// Transaction editor state and the save path.
///
/// Ports `app/add-transaction.tsx`: the expense/income control (hidden when
/// editing — the type of an existing transaction is not editable), the
/// date-time, the category/payee/group selection with the "general"/"salary"
/// defaults, and `handleSave`'s validation and row construction.
@Observable
final class TransactionEditorViewModel {
    enum Mode: Equatable {
        case new
        case edit(Transaction)

        var existing: Transaction? {
            if case .edit(let transaction) = self { return transaction }
            return nil
        }
    }

    let mode: Mode

    /// The quick-transaction template this draft was seeded from, if any. Applied
    /// once the lookups arrive — see `load`.
    let template: QuickTransaction?

    var type: String
    var amountText: String
    var descriptionText: String
    var productLinkText: String
    var date: Date
    private(set) var selectedCategoryId: String?
    private(set) var selectedPayeeId: String?
    private(set) var selectedGroupId: String?

    private(set) var lookups = TransactionService.Lookups.empty
    private(set) var validation = Validators.Result()
    private(set) var isSaving = false
    private(set) var saveErrorMessage: String?

    init(mode: Mode = .new, template: QuickTransaction? = nil) {
        self.mode = mode
        self.template = template
        let existing = mode.existing
        type = existing?.type ?? "Expense"
        amountText = existing.map { Self.text(for: $0.amount) } ?? ""
        descriptionText = existing?.description ?? ""
        productLinkText = existing?.productLink ?? ""
        date = existing.flatMap {
            TransactionTimestamp.instant(from: $0.transactionTimestamp)
        } ?? Date()
        selectedCategoryId = existing?.categoryId
        selectedPayeeId = existing?.payeeId
        selectedGroupId = existing?.groupId
    }

    /// JavaScript `amount.toString()`: a whole number has no decimal part.
    private static func text(for amount: Double) -> String {
        if amount == amount.rounded(), amount.magnitude < 1e15 {
            return String(Int(amount))
        }
        return String(amount)
    }

    // MARK: - Derived

    var isEditing: Bool { mode.existing != nil }

    /// The source hides the type control when editing.
    var typeIsEditable: Bool { !isEditing }

    var title: String { isEditing ? "Edit Transaction" : "Add Transaction" }

    var saveButtonTitle: String { "Save Transaction" }

    var selectedCategory: Category? {
        lookups.categories.first { $0.id == selectedCategoryId }
    }

    var selectedPayee: Payee? {
        lookups.payees.first { $0.id == selectedPayeeId }
    }

    var selectedGroup: TransactionGroup? {
        lookups.groups.first { $0.id == selectedGroupId }
    }

    var amountError: String? { validation.errors[.amount] }
    var descriptionError: String? { validation.errors[.description] }
    var categoryError: String? { validation.errors[.categoryId] }

    /// Categories of the selected type, plus the current selection when it does
    /// not match the type. The source can end up in that state (its default
    /// category lookup matches on name only), and dropping it would leave the
    /// picker showing nothing selected.
    var categoriesForPicker: [Category] {
        let matching = lookups.categories(ofType: type)
        guard let selected = selectedCategory, !matching.contains(where: { $0.id == selected.id })
        else { return matching }
        return matching + [selected]
    }

    // MARK: - Mutations

    func select(categoryId: String?) {
        selectedCategoryId = categoryId
        validation.errors[.categoryId] = nil
    }

    func select(payeeId: String?) { selectedPayeeId = payeeId }
    func select(groupId: String?) { selectedGroupId = groupId }

    /// Switching the type re-applies the default category, mirroring the source.
    ///
    /// For a template-prefilled draft the source's default-category effect is
    /// guarded by `!quickTx`, so the category is left exactly as the template set it,
    /// even when it does not match the new type. Preserved.
    func changeType(to newType: String) {
        guard typeIsEditable, newType != type else { return }
        type = newType
        guard template == nil else { return }
        applyDefaultCategory()
    }

    func clearErrors() {
        validation = Validators.Result()
        saveErrorMessage = nil
    }

    /// The source matches the default category by name only, ignoring the
    /// category's own type (`cats.find(c => c.name.toLowerCase() === 'general')`).
    private func applyDefaultCategory() {
        let wanted = type == "Income" ? "salary" : "general"
        if let category = lookups.firstCategory(named: wanted) {
            selectedCategoryId = category.id
        }
    }

    // MARK: - Loading

    @MainActor
    func load(pool: DatabasePool?, userId: String?) async {
        guard let pool, let userId else { return }
        do {
            lookups = try await pool.read { db in
                try TransactionService.lookups(userId: userId, in: db)
            }
        } catch {
            saveErrorMessage = error.localizedDescription
            return
        }
        if let template {
            apply(template)
        } else if !isEditing {
            applyDefaultCategory()
        }
    }

    /// The template prefill. The rules (and the quirks) are the source's — see
    /// `TransactionService.prefill`. Note it does **not** touch the product link or
    /// the group, and does not fall back to "general"/"salary" when the template has
    /// no category.
    private func apply(_ template: QuickTransaction) {
        let prefill = TransactionService.prefill(from: template, lookups: lookups)
        type = prefill.type
        if let amount = prefill.amount {
            amountText = Self.text(for: amount)
        }
        if let description = prefill.description {
            descriptionText = description
        }
        selectedCategoryId = prefill.categoryId
        selectedPayeeId = prefill.payeeId
        // The source leaves the date at "now" for a new transaction, template or
        // not, and clears any validation state.
        validation.errors[.categoryId] = nil
    }

    // MARK: - Saving

    /// Validates and writes the row. Returns true when the sheet should close.
    @MainActor
    func save(pool: DatabasePool?, userId: String?) async -> Bool {
        validation = Validators.validateTransaction(
            amount: amountText,
            description: descriptionText,
            categoryId: selectedCategoryId ?? ""
        )

        guard validation.isValid, let category = selectedCategory else { return false }
        guard
            let amount = Double(amountText.trimmingCharacters(in: .whitespacesAndNewlines)),
            Validators.amountError(amount) == nil
        else { return false }

        let draft = TransactionService.Draft(
            existing: mode.existing,
            amount: amount,
            description: descriptionText,
            date: date,
            type: type,
            category: category,
            payee: selectedPayee,
            group: selectedGroup,
            productLink: productLinkText
        )
        let record = TransactionService.makeTransaction(from: draft, userId: userId ?? "")

        guard let pool else { return false }

        isSaving = true
        defer { isSaving = false }

        do {
            try await pool.write { db in
                try TransactionService.save(record, in: db)
            }
            return true
        } catch {
            saveErrorMessage = error.localizedDescription
            return false
        }
    }
}
