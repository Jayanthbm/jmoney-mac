import Foundation
import GRDB
import Observation

/// Goal editor state and the save path.
///
/// Ports `GoalAddEditModal.tsx`: the logo URL, name, target amount and current
/// amount fields, the `validateGoal` rules, and the trimmed strings the screen
/// writes back.
///
/// Deviation, already established for the transaction and budget editors: the RN
/// modal surfaces only the *first* validation error (as a toast) and disables its
/// save button until the name is non-empty, so its name error is unreachable. Here
/// every error is shown inline and the button stays enabled, which is the only way
/// the name message can be seen. Rules and messages are unchanged.
@Observable
final class GoalEditorViewModel {
    enum Mode: Equatable {
        case new
        case edit(Goal)

        var existing: Goal? {
            if case .edit(let goal) = self { return goal }
            return nil
        }
    }

    let mode: Mode

    var name: String
    var logoText: String
    var targetAmountText: String
    var currentAmountText: String

    private(set) var validation = Validators.GoalResult()
    private(set) var isSaving = false
    private(set) var saveErrorMessage: String?

    init(mode: Mode = .new) {
        self.mode = mode
        let existing = mode.existing
        name = existing?.name ?? ""
        logoText = existing?.logo ?? ""
        targetAmountText = existing.map { Self.text(for: $0.goalAmount) } ?? ""
        currentAmountText = existing.map { Self.text(for: $0.currentAmount) } ?? ""
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

    var title: String { isEditing ? "Edit Goal" : "Add New Goal" }

    /// `editingGoal ? 'Save Changes' : 'Create Goal'`.
    var saveButtonTitle: String { isEditing ? "Save Changes" : "Create Goal" }

    var nameError: String? { validation.errors[.name] }
    var targetAmountError: String? { validation.errors[.targetAmount] }
    var currentAmountError: String? { validation.errors[.currentAmount] }

    /// A live preview of the card's progress, so the sheet shows what the form
    /// will produce. Uses the same maths as the list row.
    var previewCardInfo: GoalService.CardInfo? {
        guard
            let target = Double(targetAmountText.trimmingCharacters(in: .whitespacesAndNewlines)),
            let current = Double(currentAmountText.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return nil }
        return GoalService.cardInfo(
            Goal(
                id: "preview", name: name, logo: logoText, goalAmount: target,
                currentAmount: current, userId: "", syncStatus: 0, deleted: 0
            )
        )
    }

    func clearErrors() {
        validation = Validators.GoalResult()
        saveErrorMessage = nil
    }

    // MARK: - Saving

    /// Validates and writes the row. Returns true when the sheet should close.
    @MainActor
    func save(pool: DatabasePool?, userId: String?) async -> Bool {
        // The source validates `name.trim()`.
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        validation = Validators.validateGoal(
            name: trimmedName,
            targetAmount: targetAmountText,
            currentAmount: currentAmountText
        )
        guard validation.isValid else { return false }

        // `parseFloat(x) || 0` — both values are valid by now, so this only guards
        // the (impossible) NaN case.
        guard
            let goalAmount = Double(targetAmountText.trimmingCharacters(in: .whitespacesAndNewlines)),
            let currentAmount = Double(currentAmountText.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return false }

        guard let userId, let pool else { return false }

        let draft = GoalService.Draft(
            existing: mode.existing,
            name: trimmedName,
            logo: logoText.trimmingCharacters(in: .whitespacesAndNewlines),
            goalAmount: goalAmount,
            currentAmount: currentAmount
        )
        let record = GoalService.makeGoal(from: draft, userId: userId)

        isSaving = true
        defer { isSaving = false }

        do {
            try await pool.write { db in
                try GoalService.save(record, in: db)
            }
            return true
        } catch {
            saveErrorMessage = error.localizedDescription
            return false
        }
    }
}
