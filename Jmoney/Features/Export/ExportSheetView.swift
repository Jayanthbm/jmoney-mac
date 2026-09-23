import AppKit
import GRDB
import SwiftUI
import UniformTypeIdentifiers

/// The export sheet behind File > Export… (⌘E).
///
/// Scope (the Phase 15 brief): transactions CSV — optionally of the filtered
/// list — plus categories/payees/goals CSVs and the JSON backup. The write is
/// trivial; the sheet's job is to make the macOS convention obvious: pick a
/// location with `NSSavePanel`, get a confirmation in the status bar, and have
/// the file land where it can be revealed from Finder.
struct ExportSheetView: View {
    @Environment(AppState.self) private var appState
    @Environment(SessionStore.self) private var sessionStore
    @Environment(DatabaseService.self) private var database
    @Environment(\.dismiss) private var dismiss

    private enum Format: String, CaseIterable, Identifiable {
        case transactionsCSV = "Transactions CSV"
        case filteredCSV = "Transactions CSV (current filters)"
        case categoriesCSV = "Categories CSV"
        case payeesCSV = "Payees CSV"
        case goalsCSV = "Goals CSV"
        case jsonBackup = "Full Backup (JSON)"

        var id: String { rawValue }

        var fileExtension: String {
            switch self {
            case .jsonBackup: return "json"
            default: return "csv"
            }
        }

        var usesFilters: Bool {
            self == .filteredCSV
        }
    }

    @State private var format: Format = .transactionsCSV
    @State private var isExporting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export Data")
                .font(.title2.weight(.semibold))

            Picker("Format:", selection: $format) {
                ForEach(Format.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .accessibilityIdentifier("exportFormatPicker")

            if format.usesFilters {
                Label(
                    "Exports the transaction list exactly as it is filtered on screen.",
                    systemImage: "line.3.horizontal.decrease.circle"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            } else if format == .jsonBackup {
                Label(
                    "A complete snapshot of your data: all seven tables with sync metadata.",
                    systemImage: "archivebox"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button {
                    runExport()
                } label: {
                    if isExporting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Export…")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isExporting)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    // MARK: - Export

    private func runExport() {
        guard let pool = database.pool else {
            appState.statusMessage = "Local database isn't ready."
            return
        }
        guard let userId = sessionStore.userId else {
            appState.statusMessage = "Sign in to export your data."
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.fileExtension == "json" ? UTType.json : UTType.commaSeparatedText]
        panel.nameFieldStringValue = suggestedFileName(for: format)

        guard let url = panel.runModal() == .OK ? panel.url : nil else { return }

        isExporting = true
        dismiss()
        let selectedFormat = format
        let filters = format.usesFilters
            ? (appState.transactionsFilters ?? TransactionService.Filters())
            : TransactionService.Filters()
        Task {
            do {
                let rowText = try await pool.read { db -> String in
                    switch selectedFormat {
                    case .transactionsCSV, .filteredCSV:
                        return CSV.encode(
                            try ExportService.transactionCSVRows(
                                userId: userId, filters: filters, in: db
                            )
                        )
                    case .categoriesCSV:
                        return CSV.encode(try ExportService.categoryCSVRows(userId: userId, in: db))
                    case .payeesCSV:
                        return CSV.encode(try ExportService.payeeCSVRows(userId: userId, in: db))
                    case .goalsCSV:
                        return CSV.encode(try ExportService.goalCSVRows(userId: userId, in: db))
                    case .jsonBackup:
                        guard let json = String(
                            data: try ExportService.backupJSON(userId: userId, in: db),
                            encoding: .utf8
                        ) else {
                            throw ImportError("The backup could not be encoded.")
                        }
                        return json
                    }
                }
                try rowText.write(to: url, atomically: true, encoding: .utf8)
                appState.statusMessage = "Exported to \(url.lastPathComponent)."
            } catch {
                appState.statusMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    private func suggestedFileName(for format: Format) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: Date())
        switch format {
        case .transactionsCSV:
            return "jmoney-transactions-\(day).csv"
        case .filteredCSV:
            return "jmoney-transactions-filtered-\(day).csv"
        case .categoriesCSV:
            return "jmoney-categories-\(day).csv"
        case .payeesCSV:
            return "jmoney-payees-\(day).csv"
        case .goalsCSV:
            return "jmoney-goals-\(day).csv"
        case .jsonBackup:
            return "jmoney-backup-\(day).json"
        }
    }
}
