import SwiftUI

/// The SQLyog-style column grid shared by the Create Table and Alter Table
/// forms: header row, editable rows, add/remove, and (for Create) row
/// reordering. Operates directly on the bound `DraftColumn` array; the
/// owning view model only sees the resulting values.
struct DraftColumnsEditor: View {
    @Binding var columns: [DraftColumn]
    let dataTypes: [String]

    @State private var selectedColumnID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text("Kolonlar").font(.headline)

                Button {
                    columns.append(DraftColumn())
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
                headerRow

                ScrollView {
                    VStack(spacing: 2) {
                        ForEach($columns) { $column in
                            DraftColumnRow(
                                column: $column,
                                dataTypes: dataTypes,
                                isSelected: column.id == selectedColumnID,
                                onSelect: { selectedColumnID = column.id },
                                onDelete: { columns.removeAll { $0.id == column.id } }
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
        guard let id = selectedColumnID, let index = columns.firstIndex(where: { $0.id == id }) else { return false }
        return columns.indices.contains(index + direction)
    }

    private func moveSelected(_ direction: Int) {
        guard let id = selectedColumnID, let index = columns.firstIndex(where: { $0.id == id }) else { return }
        let newIndex = index + direction
        guard columns.indices.contains(newIndex) else { return }
        columns.swapAt(index, newIndex)
    }

    private var headerRow: some View {
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
}

private struct DraftColumnRow: View {
    @Binding var column: DraftColumn
    let dataTypes: [String]
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
                ForEach(dataTypes, id: \.self) { Text($0).tag($0) }
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
