import Foundation
import GRDB
import Observation

/// Payee editor state — the "Add New Payee" sheet.
///
/// Ports `PayeeAddModal.tsx`: the name field and the optional logo URL, with the
/// source's rule that a trimmed-empty name cannot be saved.
///
/// The same deviation as the other editors: every error is inline and Save stays
/// enabled, so the name message is reachable.
@Observable
final class PayeeEditorViewModel {
    var name = ""
    var logoText = ""

    private(set) var isSaving = false
    private(set) var saveErrorMessage: String?
    private(set) var showsNameError = false

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canSave: Bool { !trimmedName.isEmpty }

    /// `item.logo.startsWith('http')` decides between the remote image and the
    /// initial — shown live so the sheet previews the list row.
    var logoURL: URL? {
        let value = logoText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.hasPrefix("http") else { return nil }
        return URL(string: value)
    }

    var initial: String { String(trimmedName.prefix(1)).uppercased() }

    var draft: PayeeService.Draft {
        PayeeService.Draft(name: trimmedName, logo: logoText)
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

        let record = PayeeService.makePayee(from: draft, userId: userId)
        do {
            try await pool.write { db in
                try PayeeService.save(record, in: db)
            }
            return true
        } catch {
            saveErrorMessage = error.localizedDescription
            return false
        }
    }
}
