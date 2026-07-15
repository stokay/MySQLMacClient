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
/// Draws a flat custom background instead of the system header bezel, so
/// the header can use an app-chosen color pair instead of the system's.
private final class ColoredHeaderCell: NSTableHeaderCell {
    static let backgroundColor = NSColor(red: 0x3c / 255, green: 0x3c / 255, blue: 0x3c / 255, alpha: 1)
    static let textColor = NSColor(red: 0xc5 / 255, green: 0xc5 / 255, blue: 0xc5 / 255, alpha: 1)
    static let separatorColor = NSColor(red: 0xcd / 255, green: 0xcd / 255, blue: 0xcd / 255, alpha: 1)

    /// Fully replacing `draw(withFrame:in:)` (for the custom background)
    /// also threw out AppKit's own between-header-cells separator, so it's
    /// redrawn by hand on the trailing edge.
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        Self.backgroundColor.setFill()
        cellFrame.fill()
        drawInterior(withFrame: cellFrame, in: controlView)

        Self.separatorColor.setFill()
        NSRect(x: cellFrame.maxX - 1, y: cellFrame.minY, width: 1, height: cellFrame.height).fill()
    }

    /// Fully custom (no `super` call) so the title is vertically centered —
    /// the default header cell draws it flush to the top of the frame.
    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        let title = attributedStringValue
        let size = title.size()
        let textRect = NSRect(
            x: cellFrame.origin.x + 4,
            y: cellFrame.origin.y + (cellFrame.height - size.height) / 2,
            width: max(0, cellFrame.width - 8),
            height: size.height
        )
        title.draw(in: textRect)
    }
}

/// Draws the selected row's background in an app-chosen flat color instead
/// of the system's blue/gray selection highlight, and recolors its own
/// cells' text the instant `isSelected` changes.
///
/// Recoloring used to happen from `tableViewSelectionDidChange`, a
/// notification that fires *after* AppKit has already flipped the row to
/// its selected background — that gap between "background is now selected"
/// and "our delegate gets around to recoloring the text" was the flash.
/// Overriding `isSelected` here does both in the same synchronous step,
/// before any redraw happens.
private final class SelectedColorRowView: NSTableRowView {
    static let selectedBackgroundColor = NSColor(red: 0xdc / 255, green: 0xdc / 255, blue: 0xdc / 255, alpha: 1)
    static let selectedTextColor = NSColor(red: 0x22 / 255, green: 0x1a / 255, blue: 0x14 / 255, alpha: 1)

    override var isSelected: Bool {
        didSet {
            guard isSelected != oldValue else { return }
            recolorTextFields()
        }
    }

    override func drawSelection(in dirtyRect: NSRect) {
        Self.selectedBackgroundColor.setFill()
        bounds.fill()
    }

    private func recolorTextFields() {
        for cellContainer in subviews {
            for subview in cellContainer.subviews {
                guard let textField = subview as? NSTextField else { continue }
                (textField.cell as? NSTextFieldCell)?.backgroundStyle = .normal
                textField.textColor = isSelected ? Self.selectedTextColor : .labelColor
            }
        }
    }
}

struct SpreadsheetGridView: NSViewRepresentable {
    @ObservedObject var viewModel: TableDataViewModel

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = NSTableView()
        tableView.style = .plain
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.gridStyleMask = [.solidHorizontalGridLineMask, .solidVerticalGridLineMask]
        tableView.gridColor = ColoredHeaderCell.textColor
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
                let title = column.isPrimaryKey ? "🔑 \(column.name)" : column.name
                headerCell.attributedStringValue = NSAttributedString(
                    string: title,
                    attributes: [
                        .font: NSFont.boldSystemFont(ofSize: 15),
                        .foregroundColor: ColoredHeaderCell.textColor,
                    ]
                )
                tableColumn.headerCell = headerCell
                tableColumn.width = 140
                tableColumn.minWidth = 60
                tableView.addTableColumn(tableColumn)
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            viewModel.rows.count
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            SelectedColorRowView()
        }

        /// A row's `backgroundStyle` normally flips to `.emphasized` on
        /// selection, which makes an `NSTextField` briefly auto-swap to the
        /// system's own light/selected text color before our explicit
        /// `textColor` takes over — the "flash" on mouse-click select.
        /// Forcing `.normal` here makes AppKit skip that auto-adjustment,
        /// so only our own color ever applies.
        private func applyTextColor(to textField: NSTextField, isSelected: Bool) {
            (textField.cell as? NSTextFieldCell)?.backgroundStyle = .normal
            textField.textColor = isSelected ? SelectedColorRowView.selectedTextColor : .labelColor
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
                return wrapInCellView(button, centered: true)
            }

            let columnName = tableColumn.identifier.rawValue
            let textField = NSTextField(string: dataRow.editedText[columnName] ?? "")
            textField.isBordered = false
            textField.drawsBackground = false
            textField.isEditable = viewModel.hasPrimaryKey
            textField.font = .systemFont(ofSize: 12)
            applyTextColor(to: textField, isSelected: tableView.selectedRowIndexes.contains(row))
            textField.delegate = self
            textField.identifier = NSUserInterfaceItemIdentifier("\(row)|\(columnName)")
            return wrapInCellView(textField, centered: false)
        }

        /// A plain `NSView`, not `NSTableCellView` — `NSTableCellView` has
        /// its own automatic `backgroundStyle` propagation tied to row
        /// selection that kept re-asserting itself over our explicit text
        /// color on the frame the row got selected (the "flash"), even
        /// after forcing `.normal` on the cell. Nothing here relies on
        /// `NSTableCellView`'s outlets, so the plain container sidesteps
        /// that behavior entirely instead of continuing to fight it.
        private func wrapInCellView(_ subview: NSView, centered: Bool) -> NSView {
            let cell = NSView()
            subview.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(subview)
            NSLayoutConstraint.activate([
                subview.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                centered
                    ? subview.centerXAnchor.constraint(equalTo: cell.centerXAnchor)
                    : subview.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            ])
            if !centered {
                subview.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -4).isActive = true
            }
            return cell
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
