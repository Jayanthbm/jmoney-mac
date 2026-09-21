import Foundation
import GRDB
import Observation

/// Budget editor state and the save path.
///
/// Ports `BudgetAddEditModal.tsx`: the name, amount, and expense-category
/// multi-select, the `validateBudget` rules, and `handleSave`'s row
/// construction. The RN sheet's hidden fields are preserved rather than
/// invented — `interval` and `logo` keep their defaults (`Month`,
/// `account-balance-wallet`) and `start_date` is today on create and the stored
/// value on edit.
@Observable
final class BudgetEditorViewModel {
    enum Mode: Equatable {
        case new
        case edit(Budget)

        var existing: Budget? {
            if case .edit(let budget) = self { return budget }
            return nil
        }
    }

    /// The default logo the RN modal ships with (there is no logo picker).
    static let defaultLogo = "account-balance-wallet"
    /// The default interval; the RN modal has no interval control either.
    static let defaultInterval = "Month"

    let mode: Mode

    var name: String
    var amountText: String
    /// Category IDs in tap order, exactly as the source's `form.categories`. On
    /// edit this starts from the parsed column, so it can contain IDs the expense
    /// picker does not list (see `save`).
    private(set) var categoryIds: [String]
    private(set) var interval: String
    private(set) var logo: String

    private(set) var expenseCategories: [Category] = []
    private(set) var validation = Validators.BudgetResult()
    private(set) var isSaving = false
    private(set) var saveErrorMessage: String?

    init(mode: Mode = .new, calendar: Calendar = .current, now: Date = Date()) {
        self.mode = mode
        let existing = mode.existing
        name = existing?.name ?? ""
        amountText = existing.map { Self.text(for: $0.amount) } ?? ""
        // `JSON.parse(editingBudget.categories)` — decoded defensively, since the
        // source would throw on a malformed column.
        categoryIds = existing.map { BudgetService.categoryIds(from: $0.categories) } ?? []
        interval = existing?.interval ?? Self.defaultInterval
        logo = existing?.logo ?? Self.defaultLogo
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

    var title: String { isEditing ? "Edit Budget" : "New Budget" }

    var nameError: String? { validation.errors[.name] }
    var categoriesError: String? { validation.errors[.categories] }
    var amountError: String? { validation.errors[.amount] }

    /// The expense categories the picker shows — the whole selectable set, exactly
    /// as the RN chip grid renders `allCategories`.
    var categoriesForPicker: [Category] { expenseCategories }

    func isSelected(_ categoryId: String) -> Bool {
        categoryIds.contains(categoryId)
    }

    // MARK: - Mutations

    /// The RN chip toggle: remove when selected, append when not.
    func toggle(categoryId: String) {
        if let index = categoryIds.firstIndex(of: categoryId) {
            categoryIds.remove(at: index)
        } else {
            categoryIds.append(categoryId)
        }
        validation.errors[.categories] = nil
    }

    func clearErrors() {
        validation = Validators.BudgetResult()
        saveErrorMessage = nil
    }

    // MARK: - Loading

    @MainActor
    func load(pool: DatabasePool?, userId: String?) async {
        guard let pool, let userId else { return }
        do {
            expenseCategories = try await pool.read { db in
                try BudgetService.expenseCategories(userId: userId, in: db)
            }
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    // MARK: - Saving

    /// Validates and writes the row. Returns true when the sheet should close.
    @MainActor
    func save(pool: DatabasePool?, userId: String?) async -> Bool {
        validation = Validators.validateBudget(
            name: name, categories: categoryIds, amount: amountText
        )
        guard validation.isValid else { return false }

        // `parseFloat(form.amount) || 0` — the value is valid by now, so this only
        // guards the (impossible) NaN case.
        guard
            let amount = Double(amountText.trimmingCharacters(in: .whitespacesAndNewlines)),
            Validators.amountError(amount) == nil
        else { return false }

        guard let userId, let pool else { return false }

        let draft = BudgetService.Draft(
            existing: mode.existing,
            name: name,
            amount: amount,
            // Saved as-is: an ID whose category is no longer an expense is not
            // rendered as a chip but stays in the selection and is written back,
            // which is what the source does (`JSON.stringify(form.categories)`).
            categoryIds: categoryIds,
            interval: interval,
            logo: logo,
            // `editingBudget?.start_date || format(new Date(), 'yyyy-MM-dd')`
            startDate: mode.existing?.startDate ?? AppFormat.yearMonthDay(Date())
        )
        let record = BudgetService.makeBudget(from: draft, userId: userId)

        isSaving = true
        defer { isSaving = false }

        do {
            try await pool.write { db in
                try BudgetService.save(record, in: db)
            }
            return true
        } catch {
            saveErrorMessage = error.localizedDescription
            return false
        }
    }
}
