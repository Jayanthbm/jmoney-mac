import AppKit
import GRDB
import SwiftUI
import UniformTypeIdentifiers

/// The import sheet behind File > Import Transactions….
///
/// Flow: choose a CSV file (open panel, no sandbox prompt needed for a
/// user-picked file) → the first 5 rows are previewed → Import validates every
/// row and writes the valid ones in one transaction → the per-row report lists
/// every skip with its reason. Nothing is created silently: unknown category
/// or payee *names* skip their rows and are reported.
struct ImportSheetView: View {
    @Environment(AppState.self) private var appState
    @Environment(SessionStore.self) private var sessionStore
    @Environment(DatabaseService.self) private var database
    @Environment(\.dismiss) private var dismiss

    private enum Stage {
        case choose
        case preview(text: String, fileName: String)
        case report(ImportService.ImportReport)
    }

    @State private var stage: Stage = .choose
    @State private var isImporting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import Transactions")
                .font(.title2.weight(.semibold))

            switch stage {
            case .choose:
                chooseStage
            case .preview(let text, let fileName):
                previewStage(text: text, fileName: fileName)
            case .report(let report):
                reportStage(report)
            }
        }
        .padding(24)
        .frame(minWidth: 480, idealWidth: 520, minHeight: 300)
    }

    // MARK: - Choose

    @ViewBuilder
    private var chooseStage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(
                "Import transactions from a CSV file. Categories and payees are matched by name — rows that don't match are skipped, never created."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Button("Choose CSV File…") { chooseFile() }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Preview

    @ViewBuilder
    private func previewStage(text: String, fileName: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(fileName, systemImage: "doc.text")
                .font(.callout.weight(.medium))

            let rows = CSV.decode(text)
            Text("\(max(rows.count - 1, 0)) data rows found.")
                .font(.callout)
                .foregroundStyle(.secondary)

            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(rows.prefix(5).enumerated()), id: \.offset) { index, row in
                        Text(row.joined(separator: " | "))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(index == 0 ? .secondary : .primary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
            }
            .frame(maxHeight: 140)

            Text(
                "Importing marks every row for upload on the next sync. Rows failing validation (amount, category, type, dates) are skipped and reported."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Back") { stage = .choose }

                Spacer()

                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button {
                    runImport(text: text)
                } label: {
                    if isImporting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Import")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isImporting)
            }
        }
    }

    // MARK: - Report

    @ViewBuilder
    private func reportStage(_ report: ImportService.ImportReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                report.summary,
                systemImage: report.skippedCount == 0 ? "checkmark.circle" : "exclamationmark.triangle"
            )
            .font(.headline)

            if !report.results.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(
                            Array(report.results.enumerated()),
                            id: \.offset
                        ) { _, result in
                            HStack(alignment: .top, spacing: 8) {
                                Image(
                                    systemName: result.isImported
                                        ? "checkmark.circle"
                                        : "xmark.circle"
                                )
                                .foregroundStyle(result.isImported ? .green : .red)
                                .font(.callout)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Row \(result.lineNumber): \(result.description.isEmpty ? "(no description)" : result.description)")
                                        .font(.callout)
                                    if case .skipped(let reason) = result.status {
                                        Text(reason)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: - Actions

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            stage = .preview(text: text, fileName: url.lastPathComponent)
        } catch {
            appState.statusMessage = "Couldn't read the file: \(error.localizedDescription)"
        }
    }

    private func runImport(text: String) {
        guard let pool = database.pool else {
            appState.statusMessage = "Local database isn't ready."
            return
        }
        guard let userId = sessionStore.userId else {
            appState.statusMessage = "Sign in to import transactions."
            return
        }

        isImporting = true
        Task {
            do {
                let parsed = try ImportService.parse(text: text)
                let report = try await pool.write { db in
                    try ImportService.importRows(parsed, userId: userId, in: db)
                }
                isImporting = false
                stage = .report(report)
                appState.markDataChanged()
                appState.statusMessage = report.summary
            } catch {
                isImporting = false
                appState.statusMessage = "Import failed: \(error.localizedDescription)"
            }
        }
    }
}
