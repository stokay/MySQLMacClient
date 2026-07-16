import SwiftUI

/// The collapsible SQL editor panel shown above a table's grid. Running a
/// query shows its results in place of the editable grid below (see
/// `TableDataGridView`); "Tablo Görünümüne Dön" switches back.
struct QueryPanelView: View {
    @ObservedObject var viewModel: TableDataViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar

            Divider()

            SQLTextView(text: $viewModel.queryText, pendingInsertion: $viewModel.pendingQueryInsertion)
                .frame(minHeight: 70, idealHeight: 90)

            statusRow
        }
    }

    /// A full-width row right under the editor, not a small trailing
    /// caption in the toolbar — a successful run (especially a write with
    /// no visible grid change) needs a result the user can't miss.
    ///
    /// Always renders (never an empty/absent view) — the version that only
    /// showed a row when there was something to say let the whole panel's
    /// natural height flip between "with status row" and "without" as
    /// queries ran, which `VSplitView` didn't reflow cleanly for, leaving
    /// the pane visibly short with the toolbar/status clipped until the
    /// user manually dragged it. Using `.opacity` instead of removing the
    /// view keeps the reserved height constant either way.
    private var statusRow: some View {
        let (message, icon, color): (String, String, Color) = {
            if let errorMessage = viewModel.queryErrorMessage {
                return (errorMessage, "xmark.octagon.fill", .red)
            } else if let note = viewModel.queryResultEditabilityNote {
                return (note, "exclamationmark.triangle.fill", .orange)
            } else if let message = viewModel.queryMessage {
                return (message, "checkmark.circle.fill", .green)
            } else {
                return (" ", "checkmark.circle.fill", .clear)
            }
        }()

        return Label(message, systemImage: icon)
            .font(.system(size: 13))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(color == .clear ? 0 : 1)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button {
                Task { await viewModel.runQuery() }
            } label: {
                if viewModel.isExecutingQuery {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Çalıştır", systemImage: "play.fill")
                }
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(viewModel.isExecutingQuery || viewModel.queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if viewModel.isShowingQueryResult {
                Button {
                    Task { await viewModel.clearQueryResult() }
                } label: {
                    Label("Tablo Görünümüne Dön", systemImage: "tablecells")
                }
            }

            Toggle(isOn: $viewModel.isQueryResultEditableRequested) {
                Label(
                    viewModel.isQueryResultEditableRequested ? "Editable" : "Read Only",
                    systemImage: viewModel.isQueryResultEditableRequested ? "pencil" : "lock"
                )
            }
            .toggleStyle(.button)

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
