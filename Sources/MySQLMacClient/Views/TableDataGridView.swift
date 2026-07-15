import SwiftUI

/// Column set is built dynamically from the table's schema. The grid
/// itself is `SpreadsheetGridView`, an `NSTableView` wrapper — see that
/// file for why this isn't SwiftUI's native `Table`.
struct TableDataGridView: View {
    @StateObject private var viewModel: TableDataViewModel

    init(databaseName: String, tableName: String, service: MySQLService, introspection: SchemaIntrospectionService) {
        _viewModel = StateObject(wrappedValue: TableDataViewModel(
            databaseName: databaseName,
            tableName: tableName,
            service: service,
            introspection: introspection
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            if !viewModel.hasPrimaryKey && !viewModel.isLoading {
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
            } else {
                SpreadsheetGridView(viewModel: viewModel)
            }

            Divider()
            PaginationControlView(viewModel: viewModel)
        }
        .toolbar {
            ToolbarItemGroup {
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
            }
        }
        .task(id: viewModel.tableName) {
            await viewModel.load()
        }
        .navigationTitle(viewModel.tableName)
    }
}
