import SwiftUI

/// Column set is built dynamically from the table's schema. The grid
/// itself is `SpreadsheetGridView`, an `NSTableView` wrapper — see that
/// file for why this isn't SwiftUI's native `Table`.
///
/// Layout is a `VSplitView`: the SQL query panel (when open) and the grid
/// share the available height with a user-draggable divider, each pane
/// carrying its own in-view toolbar instead of the window's.
struct TableDataGridView: View {
    @StateObject private var viewModel: TableDataViewModel
    @ObservedObject var insertionBridge: SQLInsertionBridge

    init(
        databaseName: String,
        tableName: String,
        service: MySQLService,
        introspection: SchemaIntrospectionService,
        insertionBridge: SQLInsertionBridge
    ) {
        _viewModel = StateObject(wrappedValue: TableDataViewModel(
            databaseName: databaseName,
            tableName: tableName,
            service: service,
            introspection: introspection
        ))
        self.insertionBridge = insertionBridge
    }

    var body: some View {
        VSplitView {
            if viewModel.isQueryPanelVisible {
                QueryPanelView(viewModel: viewModel)
                    // Below ~150 the toolbar/editor/status row genuinely
                    // don't all fit (toolbar ~36 + divider 1 + editor's own
                    // 70 minimum + status row ~28) — the old 90 minimum was
                    // less than that, so `VSplitView` could park the pane
                    // at a height where content had to be clipped.
                    .frame(minHeight: 150, idealHeight: 180)
            }

            gridPane
                .frame(minHeight: 150)
        }
        .task(id: viewModel.tableName) {
            await viewModel.load()
        }
        .navigationTitle(viewModel.tableName)
        .onChange(of: insertionBridge.pendingText) { _, newValue in
            guard let text = newValue else { return }
            viewModel.isQueryPanelVisible = true
            viewModel.pendingQueryInsertion = text
            insertionBridge.pendingText = nil
        }
    }

    private var gridPane: some View {
        VStack(spacing: 0) {
            gridToolbar

            Divider()

            if !viewModel.hasPrimaryKey && !viewModel.isLoading && !viewModel.isShowingQueryResult {
                Label("Bu tabloda primary key yok, düzenleme kapalı.", systemImage: "exclamationmark.triangle.fill")
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.yellow.opacity(0.2))
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1))
            }

            if viewModel.isLoading && viewModel.rows.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.isShowingQueryResult {
                QueryResultGridView(
                    columnNames: viewModel.queryResultColumns,
                    rows: viewModel.queryResultRows,
                    primaryKeyColumns: Set(viewModel.queryEditContext?.primaryKeyColumns ?? []),
                    isEditable: viewModel.isQueryResultEditable,
                    onCommitEdit: { rowId, column, newText in
                        Task { await viewModel.commitQueryResultEdit(rowId: rowId, column: column, newText: newText) }
                    },
                    onDeleteRow: { row in
                        Task { await viewModel.deleteQueryResultRow(row) }
                    }
                )
            } else {
                SpreadsheetGridView(viewModel: viewModel)
            }
        }
    }

    private var gridToolbar: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.toggleQueryPanel()
            } label: {
                Label("SQL Sorgusu", systemImage: "terminal")
            }

            if !viewModel.isShowingQueryResult {
                Divider().frame(height: 16)

                Button {
                    Task { await viewModel.reload() }
                } label: {
                    Label("Yenile", systemImage: "arrow.clockwise")
                }
                Button {
                    Task { await viewModel.insertBlankRow() }
                } label: {
                    Label("Satır Ekle", systemImage: "plus")
                }
                .disabled(!viewModel.hasPrimaryKey)

                Divider().frame(height: 16)

                PaginationControlView(viewModel: viewModel)
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
