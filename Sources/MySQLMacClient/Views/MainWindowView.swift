import SwiftUI

struct MainWindowView: View {
    let session: AppSession
    let onDisconnect: () -> Void

    @StateObject private var schemaTreeViewModel: SchemaTreeViewModel
    @StateObject private var insertionBridge = SQLInsertionBridge()
    @State private var selectedTable: TableInfo?

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
                TableListView(viewModel: schemaTreeViewModel, selectedTable: $selectedTable, insertionBridge: insertionBridge)
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
    }
}
