import SwiftUI
import AppKit

/// Results grid for the SQL query panel. Read-only by default; becomes
/// editable (delete column, editable cells) when `isEditable` is true —
/// driven by the "Editable" toggle *and* `TableDataViewModel` having
/// recognized the query as a simple single-table SELECT with its primary
/// key in the result (see `QueryEditContext`). Shares header/selection
/// styling with the main grid via `GridStyling.swift`.
struct QueryResultGridView: NSViewRepresentable {
    let columnNames: [String]
    let rows: [TableRow]
    let primaryKeyColumns: Set<String>
    let isEditable: Bool
    let onCommitEdit: (TableRow.ID, String, String) -> Void
    let onDeleteRow: (TableRow) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = NSTableView()
        tableView.style = .plain
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.gridStyleMask = [.solidHorizontalGridLineMask, .solidVerticalGridLineMask]
        tableView.gridColor = .gridLineColor
        tableView.intercellSpacing = NSSize(width: 1, height: 1)
        tableView.rowHeight = 20
        tableView.headerView = NSTableHeaderView()
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        tableView.allowsColumnResizing = true
        tableView.columnAutoresizingStyle = .noColumnAutoresizing

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.drawsBackground = false

        context.coordinator.tableView = tableView
        context.coordinator.rebuildColumns(columnNames: columnNames, isEditable: isEditable)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.rows = rows
        context.coordinator.primaryKeyColumns = primaryKeyColumns
        context.coordinator.isEditable = isEditable
        context.coordinator.onCommitEdit = onCommitEdit
        context.coordinator.onDeleteRow = onDeleteRow
        context.coordinator.rebuildColumnsIfNeeded(columnNames: columnNames, isEditable: isEditable)
        context.coordinator.tableView?.reloadData()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(rows: rows, primaryKeyColumns: primaryKeyColumns, isEditable: isEditable, onCommitEdit: onCommitEdit, onDeleteRow: onDeleteRow)
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
        var rows: [TableRow]
        var primaryKeyColumns: Set<String>
        var isEditable: Bool
        var onCommitEdit: (TableRow.ID, String, String) -> Void
        var onDeleteRow: (TableRow) -> Void
        weak var tableView: NSTableView?

        private var lastColumnNames: [String] = []
        private var lastIsEditable = false
        private static let deleteColumnID = NSUserInterfaceItemIdentifier("__delete__")

        init(
            rows: [TableRow],
            primaryKeyColumns: Set<String>,
            isEditable: Bool,
            onCommitEdit: @escaping (TableRow.ID, String, String) -> Void,
            onDeleteRow: @escaping (TableRow) -> Void
        ) {
            self.rows = rows
            self.primaryKeyColumns = primaryKeyColumns
            self.isEditable = isEditable
            self.onCommitEdit = onCommitEdit
            self.onDeleteRow = onDeleteRow
        }

        func rebuildColumnsIfNeeded(columnNames: [String], isEditable: Bool) {
            guard columnNames != lastColumnNames || isEditable != lastIsEditable else { return }
            rebuildColumns(columnNames: columnNames, isEditable: isEditable)
        }

        func rebuildColumns(columnNames: [String], isEditable: Bool) {
            guard let tableView else { return }
            lastColumnNames = columnNames
            lastIsEditable = isEditable
            for column in tableView.tableColumns {
                tableView.removeTableColumn(column)
            }

            if isEditable {
                let deleteColumn = NSTableColumn(identifier: Self.deleteColumnID)
                deleteColumn.headerCell = ColoredHeaderCell()
                deleteColumn.width = 28
                deleteColumn.minWidth = 28
                deleteColumn.maxWidth = 28
                deleteColumn.resizingMask = []
                tableView.addTableColumn(deleteColumn)
            }

            for name in columnNames {
                let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(name))
                let headerCell = ColoredHeaderCell()
                let title = primaryKeyColumns.contains(name) ? "🔑 \(name)" : name
                headerCell.attributedStringValue = ColoredHeaderCell.title(title)
                column.headerCell = headerCell
                column.width = 140
                column.minWidth = 60
                tableView.addTableColumn(column)
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            rows.count
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            SelectedColorRowView()
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < rows.count, let tableColumn else { return nil }

            if tableColumn.identifier == Self.deleteColumnID {
                let button = NSButton(
                    image: NSImage(systemSymbolName: "trash", accessibilityDescription: "Sil") ?? NSImage(),
                    target: self,
                    action: #selector(deleteTapped(_:))
                )
                button.isBordered = false
                button.bezelStyle = .regularSquare
                button.tag = row
                return wrapInGridCellView(button, centered: true)
            }

            let columnName = tableColumn.identifier.rawValue
            let dataRow = rows[row]
            let textField = NSTextField(string: dataRow.editedText[columnName] ?? "")
            textField.isBordered = false
            textField.drawsBackground = false
            textField.isEditable = isEditable
            textField.font = .systemFont(ofSize: 12)
            applyGridTextColor(to: textField, isSelected: tableView.selectedRowIndexes.contains(row))
            textField.delegate = isEditable ? self : nil
            textField.identifier = NSUserInterfaceItemIdentifier("\(row)|\(columnName)")
            return wrapInGridCellView(textField, centered: false)
        }

        @objc private func deleteTapped(_ sender: NSButton) {
            let row = sender.tag
            guard row < rows.count else { return }
            onDeleteRow(rows[row])
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField,
                  let identifier = textField.identifier?.rawValue else { return }
            let parts = identifier.split(separator: "|", maxSplits: 1)
            guard parts.count == 2, let row = Int(parts[0]), row < rows.count else { return }
            let columnName = String(parts[1])
            onCommitEdit(rows[row].id, columnName, textField.stringValue)
        }
    }
}
