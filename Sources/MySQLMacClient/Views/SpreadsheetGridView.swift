import SwiftUI
import AppKit

/// `NSTableView`-backed replacement for the SwiftUI `Table` we started
/// with. SwiftUI's `Table` bakes in enough internal cell/row padding
/// (likely AppKit's own `intercellSpacing` under the hood, inaccessible
/// from the SwiftUI API) that a custom overlay could never be reliably
/// aligned with the header separator or reach the true row edges — see the
/// git history on this file for the offset-chasing that didn't converge.
/// `NSTableView` gives direct control over `intercellSpacing` and
/// `gridStyleMask`, so the header separators and the grid lines are drawn
/// by the same AppKit geometry instead of two independently-guessed ones.
/// Shared header/selection styling lives in `GridStyling.swift` — the SQL
/// query results grid (`QueryResultGridView`) reuses the same look.
struct SpreadsheetGridView: NSViewRepresentable {
    @ObservedObject var viewModel: TableDataViewModel

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
        context.coordinator.rebuildColumns()
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.viewModel = viewModel
        context.coordinator.rebuildColumnsIfNeeded()
        context.coordinator.refreshHeaderTitles()
        context.coordinator.tableView?.reloadData()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
        var viewModel: TableDataViewModel
        weak var tableView: NSTableView?
        private var lastColumnSignature: [String] = []

        private static let deleteColumnID = NSUserInterfaceItemIdentifier("__delete__")

        init(viewModel: TableDataViewModel) {
            self.viewModel = viewModel
        }

        func rebuildColumnsIfNeeded() {
            let signature = viewModel.columns.map(\.name)
            guard signature != lastColumnSignature else { return }
            lastColumnSignature = signature
            rebuildColumns()
        }

        func rebuildColumns() {
            guard let tableView else { return }
            for column in tableView.tableColumns {
                tableView.removeTableColumn(column)
            }

            let deleteColumn = NSTableColumn(identifier: Self.deleteColumnID)
            deleteColumn.headerCell = ColoredHeaderCell()
            deleteColumn.width = 28
            deleteColumn.minWidth = 28
            deleteColumn.maxWidth = 28
            deleteColumn.resizingMask = []
            tableView.addTableColumn(deleteColumn)

            for column in viewModel.columns {
                let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.name))
                let headerCell = ColoredHeaderCell()
                headerCell.attributedStringValue = headerTitle(for: column)
                tableColumn.headerCell = headerCell
                tableColumn.sortDescriptorPrototype = NSSortDescriptor(key: column.name, ascending: true)
                tableColumn.width = 140
                tableColumn.minWidth = 60
                tableView.addTableColumn(tableColumn)
            }
        }

        /// Re-applies each data column's header title/sort-arrow without
        /// touching the column structure itself — cheap enough to run on
        /// every `updateNSView`, unlike `rebuildColumns()`.
        func refreshHeaderTitles() {
            guard let tableView else { return }
            for tableColumn in tableView.tableColumns where tableColumn.identifier != Self.deleteColumnID {
                guard let headerCell = tableColumn.headerCell as? ColoredHeaderCell,
                      let column = viewModel.columns.first(where: { $0.name == tableColumn.identifier.rawValue }) else { continue }
                headerCell.attributedStringValue = headerTitle(for: column)
            }
        }

        private func headerTitle(for column: ColumnInfo) -> NSAttributedString {
            var title = column.isPrimaryKey ? "🔑 \(column.name)" : column.name
            if viewModel.sortColumn == column.name {
                title += viewModel.sortAscending ? " ▲" : " ▼"
            }
            return ColoredHeaderCell.title(title)
        }

        /// Fires when a header is clicked — AppKit itself flips the
        /// descriptor's `ascending` for a re-click on the same column, and
        /// resets to ascending for a newly-clicked different column, so we
        /// just read off whatever it decided and hand it to the view model.
        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard let descriptor = tableView.sortDescriptors.first, let key = descriptor.key else { return }
            Task { await viewModel.applySort(column: key, ascending: descriptor.ascending) }
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            viewModel.rows.count
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            SelectedColorRowView()
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < viewModel.rows.count, let tableColumn else { return nil }
            let dataRow = viewModel.rows[row]

            if tableColumn.identifier == Self.deleteColumnID {
                let button = NSButton(
                    image: NSImage(systemSymbolName: "trash", accessibilityDescription: "Sil") ?? NSImage(),
                    target: self,
                    action: #selector(deleteTapped(_:))
                )
                button.isBordered = false
                button.bezelStyle = .regularSquare
                button.tag = row
                button.isEnabled = viewModel.hasPrimaryKey
                return wrapInGridCellView(button, centered: true)
            }

            let columnName = tableColumn.identifier.rawValue
            let textField = NSTextField(string: dataRow.editedText[columnName] ?? "")
            textField.isBordered = false
            textField.drawsBackground = false
            textField.isEditable = viewModel.hasPrimaryKey
            textField.font = .systemFont(ofSize: 12)
            applyGridTextColor(to: textField, isSelected: tableView.selectedRowIndexes.contains(row))
            textField.delegate = self
            textField.identifier = NSUserInterfaceItemIdentifier("\(row)|\(columnName)")
            return wrapInGridCellView(textField, centered: false)
        }

        @objc private func deleteTapped(_ sender: NSButton) {
            let row = sender.tag
            guard row < viewModel.rows.count else { return }
            let dataRow = viewModel.rows[row]
            Task { await viewModel.deleteRow(dataRow) }
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField,
                  let identifier = textField.identifier?.rawValue else { return }
            let parts = identifier.split(separator: "|", maxSplits: 1)
            guard parts.count == 2, let row = Int(parts[0]), row < viewModel.rows.count else { return }
            let columnName = String(parts[1])
            let rowId = viewModel.rows[row].id
            let newValue = textField.stringValue
            Task { await viewModel.commitEdit(rowId: rowId, column: columnName, newText: newValue) }
        }
    }
}
