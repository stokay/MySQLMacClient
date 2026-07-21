import SwiftUI

/// A SQLyog-style "New Table" form, presented as a sheet from the window
/// toolbar's "Yeni Tablo" button. Reads the live database list off
/// `schemaTree` (rather than a snapshot) so it stays correct even if the
/// sidebar hadn't finished loading databases yet when the sheet opened.
/// The column grid is the shared `DraftColumnsEditor`.
struct CreateTableView: View {
    @StateObject private var viewModel: CreateTableViewModel
    @ObservedObject var schemaTree: SchemaTreeViewModel
    @Environment(\.dismiss) private var dismiss
    let onCreated: (TableInfo) -> Void

    init(service: MySQLService, schemaTree: SchemaTreeViewModel, defaultDatabase: String, onCreated: @escaping (TableInfo) -> Void) {
        _viewModel = StateObject(wrappedValue: CreateTableViewModel(service: service, defaultDatabase: defaultDatabase))
        self.schemaTree = schemaTree
        self.onCreated = onCreated
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Yeni Tablo")
                .font(.title2.bold())

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    DraftColumnsEditor(columns: $viewModel.columns, dataTypes: CreateTableViewModel.dataTypes)
                    sqlPreviewSection
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            HStack {
                Spacer()
                Button("İptal") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    Task {
                        if let table = await viewModel.submit() {
                            onCreated(table)
                            dismiss()
                        }
                    }
                } label: {
                    if viewModel.isSubmitting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Oluştur")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!viewModel.canSubmit)
            }
        }
        .padding(24)
        .frame(minWidth: 920, idealWidth: 960, minHeight: 640, idealHeight: 700)
        .task {
            await viewModel.loadCharsetOptions()
        }
    }

    private var header: some View {
        Form {
            LabeledContent("Tablo Adı") {
                TextField("", text: $viewModel.tableName)
                    .visibleFieldBorder()
            }
            Picker("Veritabanı", selection: $viewModel.database) {
                ForEach(schemaTree.databaseNodes) { node in
                    Text(node.info.name).tag(node.info.name)
                }
            }
            HStack(spacing: 20) {
                Picker("Engine", selection: $viewModel.engine) {
                    ForEach(CreateTableViewModel.engines, id: \.self) { Text($0).tag($0) }
                }
                Picker("Karakter Seti", selection: $viewModel.charset) {
                    ForEach(viewModel.charsetOptions, id: \.self) { Text($0).tag($0) }
                }
                Picker("Collation", selection: $viewModel.collation) {
                    ForEach(viewModel.collationOptions, id: \.self) { Text($0).tag($0) }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .gridLineColor)))
    }

    private var sqlPreviewSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SQL Önizleme").font(.headline)
            ScrollView {
                Text(viewModel.previewSQL)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 90, maxHeight: 140)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .gridLineColor)))
        }
    }
}
