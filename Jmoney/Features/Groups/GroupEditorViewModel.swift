import Foundation
import GRDB
import Observation

/// Which group the editor sheet should open for.
enum GroupEditorTarget: Identifiable, Equatable {
    case new
    case edit(TransactionGroup)

    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let group): return "edit-\(group.id)"
        }
    }

    var group: TransactionGroup? {
        if case .edit(let group) = self { return group }
        return nil
    }
}

/// Group editor state — the "New Group" sheet and the "Edit Group" sheet.
///
/// Ports the inline `GroupAddModal` / `GroupEditModal` in `app/groups.tsx`: the name
/// and optional description fields, the same trimmed write-back, and a Delete action
/// offered only when editing.
///
/// The same deviation as the other editors: every error is inline and Save stays
/// enabled, so the name message is reachable. The RN modals also disable Save while
/// the name is empty, and deleting is blocked while saving (kept).
@Observable
final class GroupEditorViewModel {
    let target: GroupEditorTarget

    var name: String
    var descriptionText: String

    private(set) var isSaving = false
    private(set) var saveErrorMessage: String?
    private(set) var showsNameError = false

    init(target: GroupEditorTarget = .new) {
        self.target = target
        let existing = target.group
        name = existing?.name ?? ""
        descriptionText = existing?.description ?? ""
    }

    var isEditing: Bool { target.group != nil }

    var title: String { isEditing ? "Edit Group" : "New Group" }

    /// `editingGroup ? 'Save Changes' : 'Save Group'`.
    var saveButtonTitle: String { isEditing ? "Save Changes" : "Save Group" }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canSave: Bool { !trimmedName.isEmpty }

    var draft: GroupService.Draft {
        GroupService.Draft(existing: target.group, name: trimmedName, description: descriptionText)
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

        let record = GroupService.makeGroup(from: draft, userId: userId)
        do {
            try await pool.write { db in
                try GroupService.save(record, in: db)
            }
            return true
        } catch {
            saveErrorMessage = error.localizedDescription
            return false
        }
    }
}
