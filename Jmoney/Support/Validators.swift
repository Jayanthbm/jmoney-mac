import Foundation

/// Ports of `src/utils/validators.ts`. Same rules and same messages
/// (DATA_ARCHITECTURE.md §2). The goal validator arrives with its phase.
enum Validators {
    /// Fields a transaction draft can fail on. The order is the source's
    /// insertion order, which decides which message the RN screen surfaces first.
    enum Field: CaseIterable {
        case amount
        case description
        case categoryId
    }

    struct Result: Equatable {
        var errors: [Field: String] = [:]

        var isValid: Bool { errors.isEmpty }

        /// The first error in the source's field order (`Object.keys(errors)[0]`
        /// in `add-transaction.tsx`).
        var firstError: String? {
            for field in Field.allCases {
                if let message = errors[field] { return message }
            }
            return nil
        }
    }

    /// `validateAmount` for a raw text field value.
    ///
    /// Unlike JS `parseFloat`, a non-numeric string is *not* silently truncated
    /// (`parseFloat('1,234')` is `1` in JS and would save ₹1). Anything that does
    /// not parse is reported as invalid — a documented, deliberate deviation.
    static func amountError(_ amount: String) -> String? {
        let trimmed = amount.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(trimmed), !value.isNaN else {
            return "Amount must be greater than 0"
        }
        return amountError(value)
    }

    /// `validateAmount` for an already-parsed number.
    static func amountError(_ amount: Double) -> String? {
        if amount.isNaN || amount <= 0 { return "Amount must be greater than 0" }
        if amount > 999_999_999 { return "Amount is too large" }
        return nil
    }

    /// Fields a budget draft can fail on, in the source's insertion order
    /// (`name`, then `categories`, then `amount`) — which decides the message the
    /// RN sheet surfaces first.
    enum BudgetField: CaseIterable {
        case name
        case categories
        case amount
    }

    struct BudgetResult: Equatable {
        var errors: [BudgetField: String] = [:]

        var isValid: Bool { errors.isEmpty }

        /// The first error in the source's field order (`Object.keys(errors)[0]`).
        var firstError: String? {
            for field in BudgetField.allCases {
                if let message = errors[field] { return message }
            }
            return nil
        }
    }

    /// `validateBudget`: name required, at least one category, valid amount.
    ///
    /// The empty-category rule is not cosmetic — the RN sync layer silently skips
    /// budgets whose category array is empty, so such a row would never reach the
    /// server (DATA_ARCHITECTURE.md §3.2). Rejecting it here is the only thing
    /// that keeps a created budget pushable.
    static func validateBudget(
        name: String,
        categories: [String],
        amount: String
    ) -> BudgetResult {
        var errors: [BudgetField: String] = [:]
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors[.name] = "Budget name is required"
        }
        if categories.isEmpty { errors[.categories] = "At least one category is required" }
        if let message = amountError(amount) { errors[.amount] = message }
        return BudgetResult(errors: errors)
    }

    /// `validateTransaction`: amount, description length, category presence.
    static func validateTransaction(
        amount: String,
        description: String,
        categoryId: String
    ) -> Result {
        var errors: [Field: String] = [:]
        if let message = amountError(amount) { errors[.amount] = message }
        if description.count > 500 { errors[.description] = "Description is too long" }
        if categoryId.isEmpty { errors[.categoryId] = "Category is required" }
        return Result(errors: errors)
    }
}
