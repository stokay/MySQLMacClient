import SwiftUI

struct PaginationControlView: View {
    @ObservedObject var viewModel: TableDataViewModel

    @State private var filterColumnSelection: String = ""
    @State private var filterText: String = ""

    /// Bound straight to `viewModel.pageSize` (not a separate local draft
    /// string) so a value typed here is already current the moment
    /// "Yenile" — which lives in the sibling grid toolbar and has no way to
    /// see this view's own local state — is clicked, with no Enter/onSubmit
    /// required first.
    private var pageSizeBinding: Binding<String> {
        Binding(
            get: { String(viewModel.pageSize) },
            set: { newValue in
                if let value = Int(newValue), value > 0 {
                    viewModel.pageSize = value
                }
            }
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("Sayfa boyutu:")
            TextField("", text: pageSizeBinding)
                .frame(width: 60)
                .onSubmit {
                    Task { await viewModel.reload() }
                }

            Divider().frame(height: 16)

            Button {
                Task { await viewModel.previousPage() }
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(viewModel.currentOffset == 0)

            Text(rangeDescription)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Button {
                Task { await viewModel.nextPage() }
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(viewModel.currentOffset + viewModel.pageSize >= viewModel.totalRowCount)

            Spacer()

            Picker("Filtre sütunu", selection: $filterColumnSelection) {
                Text("Sütun seç").tag("")
                ForEach(viewModel.columns) { column in
                    Text(column.name).tag(column.name)
                }
            }
            .labelsHidden()
            .frame(width: 140)

            TextField("Filtre değeri", text: $filterText)
                .frame(width: 160)
                .onSubmit {
                    Task {
                        await viewModel.applyFilter(
                            column: filterColumnSelection.isEmpty ? nil : filterColumnSelection,
                            value: filterText
                        )
                    }
                }

            if !filterText.isEmpty || !filterColumnSelection.isEmpty {
                Button {
                    filterColumnSelection = ""
                    filterText = ""
                    Task { await viewModel.applyFilter(column: nil, value: "") }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var rangeDescription: String {
        guard viewModel.totalRowCount > 0 else { return "0 satır" }
        let start = viewModel.currentOffset + 1
        let end = min(viewModel.currentOffset + viewModel.pageSize, viewModel.totalRowCount)
        return "\(start)–\(end) / \(viewModel.totalRowCount)"
    }
}
