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
    /// For the İnfo report's font size/color (live-updating).
    @EnvironmentObject private var settingsStore: SettingsStore

    private static let minPanelHeight: CGFloat = 180
    private static let minGridHeight: CGFloat = 150
    @State private var queryPanelHeight: CGFloat = Self.minPanelHeight
    @State private var dragStartHeight: CGFloat?
    /// Grid (default) vs. mysql-CLI-style aligned text rendering of the
    /// same rows — toggled by the two leftmost toolbar buttons.
    @State private var isTextViewMode = false

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
            if insertionBridge.pendingShowInfo {
                insertionBridge.pendingShowInfo = false
                Task { await viewModel.showTableInfo() }
            }
        }
        .onChange(of: insertionBridge.pendingShowInfo) { _, newValue in
            guard newValue else { return }
            insertionBridge.pendingShowInfo = false
            Task { await viewModel.showTableInfo() }
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

            if !viewModel.hasPrimaryKey && !viewModel.isLoading && !viewModel.isShowingQueryResult && viewModel.tableInfoText == nil {
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

            if let infoText = viewModel.tableInfoText {
                ScrollView([.vertical, .horizontal]) {
                    Text(infoText)
                        .font(.system(size: CGFloat(settingsStore.settings.info.fontSize), design: .monospaced))
                        .foregroundStyle(Color(nsColor: .settingsColor({ $0.info.textColor }, fallback: .labelColor)))
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .background(Color(nsColor: .textBackgroundColor))
            } else if viewModel.isLoading && viewModel.rows.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isTextViewMode {
                textualRowsView
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
            if viewModel.tableInfoText != nil {
                // Info report mode: the whole toolbar reduces to the way
                // back — the report is read-only, so the edit/refresh/query
                // controls would all be dead weight next to it.
                Button {
                    viewModel.tableInfoText = nil
                } label: {
                    Label("Tablo Görünümüne Dön", systemImage: "tablecells")
                }

                Text("İnfo — \(viewModel.tableName)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Spacer()
            } else {
                regularToolbarContent
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    /// The current rows (main table or query result — whichever is on
    /// screen) rendered as the same aligned plain-text table the İnfo
    /// report uses. Font/size follow the SQL editor settings, per spec.
    private var textualRowsView: some View {
        let headers: [String]
        let rows: [[String]]
        if viewModel.isShowingQueryResult {
            headers = viewModel.queryResultColumns
            rows = viewModel.queryResultRows.map { row in headers.map { row.editedText[$0] ?? "" } }
        } else {
            headers = viewModel.columns.map(\.name)
            rows = viewModel.rows.map { row in headers.map { row.editedText[$0] ?? "" } }
        }

        return ScrollView([.vertical, .horizontal]) {
            Text(TableInfoReport.textTable(headers: headers, rows: rows))
                .font(.system(size: CGFloat(settingsStore.settings.editor.fontSize), design: .monospaced))
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func viewModeButton(icon: String, fallbackSystemImage: String, help: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image.bundled(icon, fallbackSystemImage: fallbackSystemImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 5).fill(isActive ? Color.accentColor.opacity(0.22) : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(isActive ? Color.accentColor : Color.clear))
        // The inactive mode's icon reads as "disabled" (dimmed) but stays
        // clickable — that's the switch.
        .opacity(isActive ? 1 : 0.45)
        .help(help)
    }

    @ViewBuilder
    private var regularToolbarContent: some View {
        Group {
            viewModeButton(
                icon: "grid_view",
                fallbackSystemImage: "tablecells",
                help: "Izgara Görünümü",
                isActive: !isTextViewMode
            ) {
                isTextViewMode = false
            }
            viewModeButton(
                icon: "text_view",
                fallbackSystemImage: "text.justify.left",
                help: "Metin Görünümü",
                isActive: isTextViewMode
            ) {
                isTextViewMode = true
            }

            Divider().frame(height: 16)

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
    }
}
