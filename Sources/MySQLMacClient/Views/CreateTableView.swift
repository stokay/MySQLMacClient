import SwiftUI

/// A SQLyog-style "New Table" form, presented as a sheet from the window
/// toolbar's "Yeni Tablo" button. Reads the live database list off
/// `schemaTree` (rather than a snapshot) so it stays correct even if the
/// sidebar hadn't finished loading databases yet when the sheet opened.
struct CreateTableView: View {
    @StateObject private var viewModel: CreateTableViewModel
    @ObservedObject var schemaTree: SchemaTreeViewModel
    @Environment(\.dismiss) private var dismiss
    let onCreated: (TableInfo) -> Void

    @State private var selectedColumnID: UUID?

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
                    columnsSection
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
            TextField("Tablo Adı", text: $viewModel.tableName)
                .visibleFieldBorder()
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

    private var columnsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text("Kolonlar").font(.headline)

                Button {
                    viewModel.addColumn()
                } label: {
                    Label("Kolon Ekle", systemImage: "plus.circle")
                }
                .buttonStyle(.plain)

                HStack(spacing: 4) {
                    Button {
                        moveSelected(-1)
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .disabled(!canMoveSelected(-1))

                    Button {
                        moveSelected(1)
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .disabled(!canMoveSelected(1))
                }
                .buttonStyle(.plain)

                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                columnsHeaderRow

                ScrollView {
                    VStack(spacing: 2) {
                        ForEach($viewModel.columns) { $column in
                            ColumnRow(
                                column: $column,
                                isSelected: column.id == selectedColumnID,
                                onSelect: { selectedColumnID = column.id },
                                onDelete: { viewModel.removeColumn(column.id) }
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(minHeight: 180, maxHeight: 280)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .gridLineColor)))
        }
    }

    private func canMoveSelected(_ direction: Int) -> Bool {
        guard let id = selectedColumnID, let index = viewModel.columns.firstIndex(where: { $0.id == id }) else { return false }
        return viewModel.columns.indices.contains(index + direction)
    }

    private func moveSelected(_ direction: Int) {
        guard let id = selectedColumnID else { return }
        viewModel.moveColumn(id: id, direction: direction)
    }

    private var columnsHeaderRow: some View {
        HStack(spacing: 6) {
            Color.clear.frame(width: 16)
            Text("Kolon Adı").frame(width: 150, alignment: .leading)
            Text("Tip").frame(width: 110, alignment: .leading)
            Text("Uzunluk").frame(width: 64, alignment: .leading)
            Text("Varsayılan").frame(width: 90, alignment: .leading)
            Text("PK").frame(width: 24, alignment: .center)
            Text("Null Değil").frame(width: 58, alignment: .center)
            Text("Unsigned").frame(width: 58, alignment: .center)
            Text("Oto Artış").frame(width: 58, alignment: .center)
            Text("Açıklama").frame(minWidth: 100, alignment: .leading)
            Spacer(minLength: 20)
        }
        .font(.caption.bold())
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
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

private struct ColumnRow: View {
    @Binding var column: CreateTableViewModel.DraftColumn
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .contentShape(Rectangle())
                .onTapGesture { onSelect() }

            TextField("", text: $column.name)
                .visibleFieldBorder(padding: 4, cornerRadius: 4)
                .frame(width: 150)
            Picker("", selection: $column.dataType) {
                ForEach(CreateTableViewModel.dataTypes, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .frame(width: 110)
            TextField("", text: $column.length)
                .visibleFieldBorder(padding: 4, cornerRadius: 4)
                .frame(width: 64)
            TextField("", text: $column.defaultValue)
                .visibleFieldBorder(padding: 4, cornerRadius: 4)
                .frame(width: 90)
            Toggle("", isOn: $column.isPrimaryKey)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .frame(width: 24)
            Toggle("", isOn: $column.isNotNull)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .frame(width: 58)
                .disabled(column.isPrimaryKey)
            Toggle("", isOn: $column.isUnsigned)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .frame(width: 58)
            Toggle("", isOn: $column.isAutoIncrement)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .frame(width: 58)
            TextField("", text: $column.comment)
                .visibleFieldBorder(padding: 4, cornerRadius: 4)
                .frame(minWidth: 100)

            Button {
                onDelete()
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .frame(width: 20)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
    }
}
