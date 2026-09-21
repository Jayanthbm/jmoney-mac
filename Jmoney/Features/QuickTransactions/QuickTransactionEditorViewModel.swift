import Foundation
import GRDB
import Observation

/// Which template the editor sheet should open for.
enum QuickTransactionEditorTarget: Identifiable, Equatable {
    case new
    case edit(QuickTransaction)

    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let template): return "edit-\(template.id)"
        }
    }

    var template: QuickTransaction? {
        if case .edit(let template) = self { return template }
        return nil
    }
}

/// Template editor state — the `add-quick-transaction` screen.
///
/// Ports `app/add-quick-transaction.tsx`: the name (required), the Expense/Income
/// control, the category and payee pickers with the same "general"/"salary" defaults,
/// the amount, description, product link and `identifier` fields, and the
/// `validateAmount` rule — which is only applied **when an amount is present**,
/// because a template may be deliberately "flexible".
///
/// The same deviation as the other editors: the name error is inline rather than a
/// toast. The rule and its message ("Please enter a name for this template") are the
/// source's.
@Observable
final class QuickTransactionEditorViewModel {
    let target: QuickTransactionEditorTarget

    var name: String
    var kind: QuickTransactionService.Kind
    var amountText: String
    var descriptionText: String
    var productLinkText: String
    var identifier: String

    private(set) var categoryId: String?
    private(set) var payeeId: String?

    private(set) var lookups = TransactionService.Lookups.empty
    private(set) var amountError: String?
    private(set) var nameError: String?
    private(set) var isSaving = false
    private(set) var saveErrorMessage: String?

    init(target: QuickTransactionEditorTarget = .new) {
        self.target = target
        let existing = target.template
        name = existing?.name ?? ""
        kind = existing.flatMap { QuickTransactionService.Kind(rawValue: $0.type) } ?? .expense
        amountText = existing?.amount.map { Self.text(for: $0) } ?? ""
        descriptionText = existing?.description ?? ""
        productLinkText = existing?.productLink ?? ""
        identifier = existing?.identifier ?? ""
        categoryId = existing?.categoryId
        payeeId = existing?.payeeId
    }

    /// JavaScript `amount.toString()`: a whole number has no decimal part.
    private static func text(for amount: Double) -> String {
        if amount == amount.rounded(), amount.magnitude < 1e15 {
            return String(Int(amount))
        }
        return String(amount)
    }

    // MARK: - Derived

    var isEditing: Bool { target.template != nil }

    var title: String { isEditing ? "Edit Template" : "New Template" }

    /// `editingTemplate ? 'Save Changes' : 'Save Template'`.
    var saveButtonTitle: String { isEditing ? "Save Changes" : "Save Template" }

    var amountIsOptional: Bool { true }

    /// Categories of the selected type, plus the current selection when it does not
    /// match — the same guard the transaction editor uses.
    var categoriesForPicker: [Category] {
        let matching = lookups.categories(ofType: kind.rawValue)
        guard let categoryId,
              let selected = lookups.categories.first(where: { $0.id == categoryId }),
              !matching.contains(where: { $0.id == selected.id })
        else { return matching }
        return matching + [selected]
    }

    var selectedCategory: Category? {
        lookups.categories.first { $0.id == categoryId }
    }

    var selectedPayee: Payee? {
        lookups.payees.first { $0.id == payeeId }
    }

    // MARK: - Mutations

    func select(categoryId: String?) {
        self.categoryId = categoryId
        nameError = nil
    }

    func select(payeeId: String?) { self.payeeId = payeeId }

    /// Switching the type re-applies the default category, mirroring the source —
    /// but only for a template that is not being edited, exactly as the screen
    /// guards it (`if (!editQt && categories.length > 0)`).
    func changeKind(to newKind: QuickTransactionService.Kind) {
        guard newKind != kind else { return }
        kind = newKind
        guard !isEditing else { return }
        applyDefaultCategory()
    }

    func clearErrors() {
        amountError = nil
        nameError = nil
        saveErrorMessage = nil
    }

    private func applyDefaultCategory() {
        let wanted = kind == .income ? "salary" : "general"
        if let category = lookups.firstCategory(named: wanted) {
            categoryId = category.id
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
        // The source drops a template's category/payee when the referenced row no
        // longer exists (the `find` returns undefined and the state stays null).
        if categoryId != nil, selectedCategory == nil { categoryId = nil }
        if payeeId != nil, selectedPayee == nil { payeeId = nil }
        if !isEditing { applyDefaultCategory() }
    }

    // MARK: - Saving

    /// Validates and writes the row. Returns true when the sheet should close.
    @MainActor
    func save(pool: DatabasePool?, userId: String?) async -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        nameError = trimmedName.isEmpty ? "Please enter a name for this template" : nil

        // The amount is validated only when one was typed — a template may be
        // "flexible". The source checks `if (amount)`.
        let trimmedAmount = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        amountError = trimmedAmount.isEmpty ? nil : Validators.amountError(trimmedAmount)

        guard nameError == nil, amountError == nil else { return false }
        guard let pool, let userId else { return false }

        var amount: Double?
        if !trimmedAmount.isEmpty {
            guard let parsed = Double(trimmedAmount), Validators.amountError(parsed) == nil else {
                amountError = Validators.amountError(trimmedAmount)
                return false
            }
            amount = parsed
        }

        let draft = QuickTransactionService.Draft(
            existing: target.template,
            name: trimmedName,
            type: kind,
            amount: amount,
            categoryId: categoryId,
            payeeId: payeeId,
            description: descriptionText,
            productLink: productLinkText,
            identifier: identifier
        )
        let record = QuickTransactionService.makeQuickTransaction(from: draft, userId: userId)

        isSaving = true
        defer { isSaving = false }

        do {
            try await pool.write { db in
                try QuickTransactionService.save(record, in: db)
            }
            return true
        } catch {
            saveErrorMessage = error.localizedDescription
            return false
        }
    }
}
