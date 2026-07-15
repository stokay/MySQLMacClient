import Foundation

/// One fetched row. `originalValues` is the snapshot from the moment of the
/// fetch (used to build PK-based WHERE clauses so edits never go stale), and
/// `editedText` is the live, per-cell text shown/edited in the grid.
struct TableRow: Identifiable {
    let id = UUID()
    private(set) var originalValues: [String: RowValue]
    var editedText: [String: String]

    init(values: [String: RowValue]) {
        self.originalValues = values
        self.editedText = values.mapValues { $0.displayString }
    }

    func isDirty(_ column: String) -> Bool {
        editedText[column] != (originalValues[column]?.displayString ?? "")
    }

    var isRowDirty: Bool {
        originalValues.keys.contains { isDirty($0) }
    }

    /// Call after a successful UPDATE so the edited columns stop being "dirty".
    mutating func acceptEdits(for columnNames: [String]) {
        for column in columnNames {
            guard let text = editedText[column] else { continue }
            originalValues[column] = text.isEmpty ? .null : .string(text)
        }
    }
}
