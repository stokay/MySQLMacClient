import SwiftUI

struct MainWindowView: View {
    let session: AppSession
    let onDisconnect: () -> Void

    @StateObject private var schemaTreeViewModel: SchemaTreeViewModel
    @StateObject private var insertionBridge = SQLInsertionBridge()
    @State private var selectedTable: TableInfo?
    @State private var isShowingCreateTable = false
    /// Set when the create-table sheet is opened from a table's context
    /// menu, so the form pre-selects that table's database instead of the
    /// currently selected one.
    @State private var createTableDefaultDatabase: String?
    @State private var tablePendingTruncate: TableInfo?
    @State private var tablePendingDrop: TableInfo?
    @State private var tableToAlter: TableInfo?
    @State private var contextActionError: String?

    init(session: AppSession, onDisconnect: @escaping () -> Void) {
        self.session = session
        self.onDisconnect = onDisconnect
        _schemaTreeViewModel = StateObject(
            wrappedValue: SchemaTreeViewModel(introspection: session.introspectionService)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                TableListView(
                    viewModel: schemaTreeViewModel,
                    selectedTable: $selectedTable,
                    insertionBridge: insertionBridge,
                    onCreateTable: { database in
                        createTableDefaultDatabase = database
                        isShowingCreateTable = true
                    },
                    onTruncateTable: { tablePendingTruncate = $0 },
                    onDropTable: { tablePendingDrop = $0 },
                    onInsertQueryTemplate: { table, kind in
                        Task { await insertQueryTemplate(for: table, kind: kind) }
                    },
                    onAlterTable: { tableToAlter = $0 },
                    onShowTableInfo: { table in
                        selectedTable = table
                        insertionBridge.pendingShowInfo = true
                    }
                )
                .navigationSplitViewColumnWidth(min: 200, ideal: 260)
            } detail: {
                if let selectedTable {
                    TableDataGridView(
                        databaseName: selectedTable.database,
                        tableName: selectedTable.name,
                        service: session.mysqlService,
                        introspection: session.introspectionService,
                        insertionBridge: insertionBridge
                    )
                    .id(selectedTable.id)
                } else {
                    VStack {
                        Image(systemName: "tablecells")
                            .font(.system(size: 40))
                            .foregroundStyle(.tertiary)
                        Text("Bir tablo seçin")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            StatusBarView(profile: session.profile, onDisconnect: onDisconnect)
        }
        .task {
            await schemaTreeViewModel.loadDatabases()
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    createTableDefaultDatabase = nil
                    isShowingCreateTable = true
                } label: {
                    Label {
                        Text("Yeni Tablo")
                    } icon: {
                        Image.bundled("create_table", fallbackSystemImage: "tablecells.badge.plus")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 30, height: 30)
                    }
                }
                .help("Yeni Tablo Oluştur")
            }
        }
        .sheet(isPresented: $isShowingCreateTable) {
            CreateTableView(
                service: session.mysqlService,
                schemaTree: schemaTreeViewModel,
                defaultDatabase: createTableDefaultDatabase
                    ?? selectedTable?.database
                    ?? schemaTreeViewModel.databaseNodes.first?.info.name
                    ?? ""
            ) { createdTable in
                Task {
                    if let node = schemaTreeViewModel.databaseNodes.first(where: { $0.info.name == createdTable.database }) {
                        await node.reload()
                    }
                    selectedTable = createdTable
                }
            }
        }
        .sheet(item: $tableToAlter) { table in
            AlterTableView(service: session.mysqlService, table: table) { alteredTable in
                Task {
                    if let node = schemaTreeViewModel.databaseNodes.first(where: { $0.info.name == alteredTable.database }) {
                        await node.reload()
                    }
                    // Bounce the selection so the grid rebuilds with the new
                    // schema even when the table kept its name (same
                    // reasoning as the truncate refresh below).
                    selectedTable = nil
                    try? await Task.sleep(for: .milliseconds(50))
                    selectedTable = alteredTable
                }
            }
        }
        .confirmationDialog(
            "'\(tablePendingTruncate?.name ?? "")' tablosundaki TÜM satırlar silinsin mi?",
            isPresented: Binding(
                get: { tablePendingTruncate != nil },
                set: { if !$0 { tablePendingTruncate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Truncate", role: .destructive) {
                if let table = tablePendingTruncate {
                    Task { await truncateTable(table) }
                }
                tablePendingTruncate = nil
            }
            Button("İptal", role: .cancel) { tablePendingTruncate = nil }
        } message: {
            Text("TRUNCATE TABLE geri alınamaz.")
        }
        .confirmationDialog(
            "'\(tablePendingDrop?.name ?? "")' tablosu tamamen silinsin mi?",
            isPresented: Binding(
                get: { tablePendingDrop != nil },
                set: { if !$0 { tablePendingDrop = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Drop", role: .destructive) {
                if let table = tablePendingDrop {
                    Task { await dropTable(table) }
                }
                tablePendingDrop = nil
            }
            Button("İptal", role: .cancel) { tablePendingDrop = nil }
        } message: {
            Text("DROP TABLE tabloyu yapısıyla birlikte kalıcı olarak siler, geri alınamaz.")
        }
        .alert(
            "Hata",
            isPresented: Binding(
                get: { contextActionError != nil },
                set: { if !$0 { contextActionError = nil } }
            )
        ) {
            Button("Tamam", role: .cancel) { contextActionError = nil }
        } message: {
            Text(contextActionError ?? "")
        }
    }

    /// "SQL Sorgu Ekle" context-menu action: fetches the table's real
    /// column list, builds the statement skeleton, and routes it through
    /// the insertion bridge. The table is selected first so the grid (and
    /// with it the query panel that consumes the bridge) actually exists.
    private func insertQueryTemplate(for table: TableInfo, kind: SQLTemplate.Kind) async {
        let columns: [ColumnInfo]
        do {
            columns = try await session.introspectionService.columns(forTable: table.name, inDatabase: table.database)
        } catch {
            contextActionError = "Kolonlar alınamadı: \(error.localizedDescription)"
            return
        }

        selectedTable = table
        insertionBridge.pendingAppend = SQLTemplate.generate(
            kind,
            database: table.database,
            table: table.name,
            columns: columns
        )
    }

    private func truncateTable(_ table: TableInfo) async {
        do {
            let qualified = try SchemaIntrospectionService.qualifiedIdentifier(database: table.database, name: table.name)
            try await session.mysqlService.execute("TRUNCATE TABLE \(qualified)")
        } catch {
            contextActionError = "Truncate başarısız: \(error.localizedDescription)"
            return
        }

        // The grid view's identity is keyed by `selectedTable.id`, which
        // doesn't change here — bouncing the selection through nil (across
        // two separate UI updates) is what forces a fresh grid that reloads
        // the now-empty table.
        if selectedTable?.id == table.id {
            selectedTable = nil
            try? await Task.sleep(for: .milliseconds(50))
            selectedTable = table
        }
    }

    private func dropTable(_ table: TableInfo) async {
        do {
            let qualified = try SchemaIntrospectionService.qualifiedIdentifier(database: table.database, name: table.name)
            try await session.mysqlService.execute("DROP TABLE \(qualified)")
        } catch {
            contextActionError = "Drop başarısız: \(error.localizedDescription)"
            return
        }

        if selectedTable?.id == table.id {
            selectedTable = nil
        }
        if let node = schemaTreeViewModel.databaseNodes.first(where: { $0.info.name == table.database }) {
            await node.reload()
        }
    }
}
