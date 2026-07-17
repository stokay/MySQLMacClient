import SwiftUI

/// Column set is built dynamically from the table's schema. The grid
/// itself is `SpreadsheetGridView`, an `NSTableView` wrapper — see that
/// file for why this isn't SwiftUI's native `Table`.
///
/// The SQL query panel (when open) sits above the grid with a draggable
/// divider between them. This is deliberately *not* a `VSplitView`:
/// `VSplitView` decides pane heights itself when a pane first appears, and
/// it repeatedly opened the query panel squeezed below its content's real
/// minimum (toolbar crushed under the window toolbar) no matter what
/// min/ideal frames the pane declared. Owning the height in a `@State` and
/// applying it as an exact `.frame(height:)` makes a squeezed first layout
/// impossible, at the cost of hand-rolling the divider drag.
struct TableDataGridView: View {
    @StateObject private var viewModel: TableDataViewModel
    @ObservedObject var insertionBridge: SQLInsertionBridge

    private static let minPanelHeight: CGFloat = 180
    private static let minGridHeight: CGFloat = 150
    @State private var queryPanelHeight: CGFloat = Self.minPanelHeight
    @State private var dragStartHeight: CGFloat?

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
        GeometryReader { geometry in
            VStack(spacing: 0) {
                if viewModel.isQueryPanelVisible {
                    QueryPanelView(viewModel: viewModel)
                        .frame(height: clampedPanelHeight(totalHeight: geometry.size.height))

                    splitDivider(totalHeight: geometry.size.height)
                }

                gridPane
                    .frame(maxHeight: .infinity)
            }
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
        .onChange(of: insertionBridge.pendingAppend) { _, newValue in
            guard let text = newValue else { return }
            viewModel.isQueryPanelVisible = true
            viewModel.pendingQueryAppend = text
            insertionBridge.pendingAppend = nil
        }
        // `.onChange` only fires on *changes after* this view exists — when
        // the context menu selects a table whose grid wasn't open yet, the
        // bridge is written before this view is created, so the value must
        // also be consumed once at appearance.
        .onAppear {
            if let text = insertionBridge.pendingAppend {
                viewModel.isQueryPanelVisible = true
                viewModel.pendingQueryAppend = text
                insertionBridge.pendingAppend = nil
            }
        }
    }

    /// The panel never renders below its content's real minimum, and the
    /// grid always keeps at least `minGridHeight` — whichever way the user
    /// drags or the window resizes.
    private func clampedPanelHeight(totalHeight: CGFloat) -> CGFloat {
        let maxAllowed = max(Self.minPanelHeight, totalHeight - Self.minGridHeight)
        return min(max(queryPanelHeight, Self.minPanelHeight), maxAllowed)
    }

    private func splitDivider(totalHeight: CGFloat) -> some View {
        Rectangle()
            .fill(Color(nsColor: .gridLineColor))
            .frame(height: 5)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if dragStartHeight == nil {
                            dragStartHeight = clampedPanelHeight(totalHeight: totalHeight)
                        }
                        queryPanelHeight = (dragStartHeight ?? Self.minPanelHeight) + value.translation.height
                    }
                    .onEnded { _ in
                        queryPanelHeight = clampedPanelHeight(totalHeight: totalHeight)
                        dragStartHeight = nil
                    }
            )
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
