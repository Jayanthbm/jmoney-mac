import SwiftUI

/// Reports — the index of the eleven reports, replacing the RN reports tab.
///
/// The mobile layout maps onto Mac as a `NavigationStack`: the index is the root
/// (with the RN grid/list toggle kept as a toolbar button, persisted under the
/// same `reports_view_mode` key), and each report is pushed on top of it.
///
/// The dashboard's click-through (`AppState.openReport`) and the reports section
/// share this stack: `AppState.requestedReport` is consumed on appear and pushed,
/// so a dashboard card lands directly on its report instead of on the index.
struct ReportsView: View {
    @Environment(AppState.self) private var appState

    @State private var viewModel = ReportsViewModel()
    @State private var path: [ReportDestination] = []

    var body: some View {
        NavigationStack(path: $path) {
            indexContent
                .navigationTitle("Reports")
                .navigationDestination(for: ReportDestination.self) { destination in
                    ReportDetailView(destination: destination)
                }
                .toolbar { toolbarContent }
        }
        .onAppear(perform: consumeRequestedReport)
        .onChange(of: appState.requestedReport) { _, _ in consumeRequestedReport() }
    }

    /// The dashboard hands a report over through `AppState`; clearing it here is
    /// what makes the handoff one-shot.
    private func consumeRequestedReport() {
        guard let destination = appState.consumeRequestedReport() else { return }
        path = [destination]
    }

    private var indexContent: some View {
        VStack(spacing: 0) {
            header
            Divider()
            switch viewModel.viewMode {
            case .list: listLayout
            case .grid: gridLayout
            }
        }
    }

    /// The RN header row: a caption and the view-mode toggle.
    private var header: some View {
        HStack(spacing: 12) {
            Text("Choose a report to view")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Button {
                viewModel.toggleViewMode()
            } label: {
                Label(viewModel.viewMode.title, systemImage: viewModel.viewMode.icon)
                    .font(.callout.weight(.bold))
            }
            .buttonStyle(.bordered)
            .help("Switch between the list and grid layouts")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var listLayout: some View {
        List(viewModel.reports) { destination in
            NavigationLink(value: destination) {
                HStack(spacing: 12) {
                    iconBox(for: destination, size: 44, glyphSize: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(destination.title)
                            .font(.body.weight(.bold))
                        Text(destination.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .listStyle(.inset)
    }

    private var gridLayout: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 200, maximum: 320), spacing: 16)],
                spacing: 16
            ) {
                ForEach(viewModel.reports) { destination in
                    NavigationLink(value: destination) {
                        gridCard(for: destination)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
    }

    private func gridCard(for destination: ReportDestination) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            iconBox(for: destination, size: 52, glyphSize: 28)
            Text(destination.title)
                .font(.headline)
                .lineLimit(1)
            Text(destination.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16).strokeBorder(.separator)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func iconBox(for destination: ReportDestination, size: Double, glyphSize: Double)
        -> some View {
        Image(systemName: destination.icon)
            .font(.system(size: glyphSize, weight: .semibold))
            .foregroundStyle(destination.color)
            .frame(width: size, height: size)
            .background(destination.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityHidden(true)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem {
            Button {
                viewModel.toggleViewMode()
            } label: {
                Label(viewModel.viewMode.title, systemImage: viewModel.viewMode.icon)
            }
            .help("Switch between the list and grid layouts")
        }
    }
}
