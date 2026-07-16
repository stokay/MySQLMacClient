import AppKit

/// Shared look for every `NSTableView`-backed grid in the app (the main
/// editable table grid and the SQL query results grid) — kept in one place
/// so the two don't visually drift apart.

extension NSColor {
    /// A color that resolves differently depending on the app's *current*
    /// effective appearance (`AppearanceStore` sets `NSApp.appearance`
    /// directly, since this is a manual in-app override, not the system
    /// Light/Dark setting) — resolved fresh on every draw, not just once.
    static func adaptive(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }

    /// Row/column separator lines for the data grids. Used to just reuse
    /// the header's text color (`#c5c5c5`), which reads fine against a
    /// light row but far too bright/white against a dark-mode row
    /// background — a dedicated, per-appearance gray instead.
    static let gridLineColor = NSColor.adaptive(
        light: NSColor(red: 0xc5 / 255, green: 0xc5 / 255, blue: 0xc5 / 255, alpha: 1),
        dark: NSColor(red: 0x48 / 255, green: 0x48 / 255, blue: 0x48 / 255, alpha: 1)
    )
}

/// Draws a flat custom background instead of the system header bezel, so
/// the header can use an app-chosen color pair instead of the system's.
final class ColoredHeaderCell: NSTableHeaderCell {
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

    static func title(_ text: String, bold: Bool = true) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: bold ? NSFont.boldSystemFont(ofSize: 15) : NSFont.systemFont(ofSize: 15),
                .foregroundColor: textColor,
            ]
        )
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
final class SelectedColorRowView: NSTableRowView {
    static let selectedBackgroundColor = NSColor.adaptive(
        light: NSColor(red: 0xdc / 255, green: 0xdc / 255, blue: 0xdc / 255, alpha: 1),
        dark: NSColor(red: 0x55 / 255, green: 0x55 / 255, blue: 0x55 / 255, alpha: 1)
    )
    static let selectedTextColor = NSColor.adaptive(
        light: NSColor(red: 0x22 / 255, green: 0x1a / 255, blue: 0x14 / 255, alpha: 1),
        dark: NSColor(red: 0xf5 / 255, green: 0xf0 / 255, blue: 0xe8 / 255, alpha: 1)
    )

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

/// A row's `backgroundStyle` normally flips to `.emphasized` on selection,
/// which makes an `NSTextField` briefly auto-swap to the system's own
/// light/selected text color before an explicit `textColor` takes over —
/// the "flash" on mouse-click select. Forcing `.normal` makes AppKit skip
/// that auto-adjustment, so only the explicit color ever applies.
@MainActor
func applyGridTextColor(to textField: NSTextField, isSelected: Bool) {
    (textField.cell as? NSTextFieldCell)?.backgroundStyle = .normal
    textField.textColor = isSelected ? SelectedColorRowView.selectedTextColor : .labelColor
}

/// A plain `NSView`, not `NSTableCellView` — `NSTableCellView` has its own
/// automatic `backgroundStyle` propagation tied to row selection that kept
/// re-asserting itself over an explicit text color on the frame a row got
/// selected (the "flash"), even after forcing `.normal` on the cell.
/// Nothing in these grids relies on `NSTableCellView`'s outlets, so the
/// plain container sidesteps that behavior entirely.
@MainActor
func wrapInGridCellView(_ subview: NSView, centered: Bool) -> NSView {
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
