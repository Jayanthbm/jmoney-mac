import Foundation
import GRDB
import Observation

/// Category editor state — the "New Category" sheet.
///
/// Ports `CategoryAddModal.tsx`: the name field, the Expense/Income control, and the
/// Material icon name field. There is no edit mode, because the source's categories
/// screen has no edit path.
///
/// Deviation, already established for the transaction/budget/goal editors: the RN
/// modal surfaces only the *first* validation error (a toast) and disables Save
/// until the name is non-empty, so the name error is unreachable. Here the error is
/// inline and Save stays enabled, which is the only way that message can be seen.
/// The rule itself is unchanged: a trimmed-empty name cannot be saved.
@Observable
final class CategoryEditorViewModel {
    var name = ""
    var kind: CategoryService.Kind = .expense
    var appIcon = ""

    private(set) var isSaving = false
    private(set) var saveErrorMessage: String?
    private(set) var showsNameError = false

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The source's disabled-Save rule.
    var canSave: Bool { !trimmedName.isEmpty }

    /// The glyph the current icon field resolves to, so the sheet previews exactly
    /// what the list will draw — including the source's `'category'` default for an
    /// empty field, which `categorySymbol` supplies.
    var previewSymbolName: String { CategoryIcon.categorySymbol(appIcon) }

    var draft: CategoryService.Draft {
        CategoryService.Draft(name: trimmedName, type: kind, appIcon: appIcon)
    }

    func clearErrors() {
        saveErrorMessage = nil
        showsNameError = false
    }

    /// Validates and writes the row. Returns true when the sheet should close.
    @MainActor
    func save(pool: DatabasePool?, userId: String?) async -> Bool {
        guard canSave else {
            showsNameError = true
            return false
        }
        guard let pool, let userId else { return false }

        isSaving = true
        defer { isSaving = false }

        let record = CategoryService.makeCategory(from: draft, userId: userId)
        do {
            try await pool.write { db in
                try CategoryService.save(record, in: db)
            }
            return true
        } catch {
            saveErrorMessage = error.localizedDescription
            return false
        }
    }
}
