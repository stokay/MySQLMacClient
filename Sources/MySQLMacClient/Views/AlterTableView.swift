import SwiftUI

/// The "Alter Table" sheet, opened from a table's context menu in the
/// sidebar. Same layout as `CreateTableView`, but the column grid arrives
/// pre-filled with the live schema and the SQL preview shows the *diff* as
/// a single `ALTER TABLE` statement (or a "no changes" note).
struct AlterTableView: View {
    @StateObject private var viewModel: AlterTableViewModel
    @Environment(\.dismiss) private var dismiss
    let onAltered: (TableInfo) -> Void

    init(service: MySQLService, table: TableInfo, onAltered: @escaping (TableInfo) -> Void) {
        _viewModel = StateObject(wrappedValue: AlterTableViewModel(service: service, table: table))
        self.onAltered = onAltered
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Alter Table — \(viewModel.originalTableName)")
                .font(.title2.bold())

            if viewModel.isLoading {
                ProgressView("Tablo yapısı yükleniyor…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        DraftColumnsEditor(
                            columns: $viewModel.columns,
                            dataTypes: viewModel.availableDataTypes
                        )
                        sqlPreviewSection
                    }
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
                            onAltered(table)
                            dismiss()
                        }
                    }
                } label: {
                    if viewModel.isSubmitting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Uygula")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!viewModel.canSubmit)
            }
        }
        .padding(24)
        .frame(minWidth: 920, idealWidth: 960, minHeight: 640, idealHeight: 700)
        .task {
            await viewModel.load()
        }
    }

    private var header: some View {
        Form {
            LabeledContent("Tablo Adı") {
                TextField("", text: $viewModel.tableName)
                    .visibleFieldBorder()
            }
            LabeledContent("Veritabanı") {
                Text(viewModel.database)
                    .foregroundStyle(.secondary)
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
