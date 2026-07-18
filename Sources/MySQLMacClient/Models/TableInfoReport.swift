import Foundation

/// Renders the "İnfo" report — the mysql-CLI-style plain-text summary of a
/// table (columns, indexes, DDL) shown in the grid pane. Pure string
/// building; the view model supplies the query results as ordered
/// header/row string arrays.
enum TableInfoReport {
    /// `/*Title*/` over a dash rule of the same width, as in SQLyog's info
    /// tab.
    static func sectionHeader(_ title: String) -> String {
        let line = "/*\(title)*/"
        return "\(line)\n\(String(repeating: "-", count: line.count))"
    }

    /// Monospace-aligned text table: each column as wide as its widest
    /// cell/header, two spaces between columns, dash rule under the header.
    /// Purely numeric values are right-aligned (as the mysql CLI does),
    /// everything else left-aligned.
    static func textTable(headers: [String], rows: [[String]]) -> String {
        guard !headers.isEmpty else { return "" }

        var widths = headers.map(\.count)
        for row in rows {
            for (index, cell) in row.enumerated() where index < widths.count {
                widths[index] = max(widths[index], cell.count)
            }
        }

        func pad(_ text: String, toWidth width: Int, rightAligned: Bool) -> String {
            let padding = String(repeating: " ", count: max(0, width - text.count))
            return rightAligned ? padding + text : text + padding
        }

        // Trailing pad spaces on a line's last cell are invisible noise
        // (and they leak into copy/paste), so each finished line is
        // right-trimmed.
        func rightTrimmed(_ line: String) -> String {
            String(line.reversed().drop { $0 == " " }.reversed())
        }

        var lines: [String] = []
        lines.append(rightTrimmed(headers.enumerated().map { pad($0.element, toWidth: widths[$0.offset], rightAligned: false) }.joined(separator: "  ")))
        lines.append(widths.map { String(repeating: "-", count: $0) }.joined(separator: "  "))
        for row in rows {
            let cells = row.enumerated().map { index, cell in
                let isNumeric = !cell.isEmpty && cell.allSatisfy { $0.isNumber || $0 == "-" } && cell != "-"
                return pad(cell, toWidth: index < widths.count ? widths[index] : cell.count, rightAligned: isNumeric)
            }
            lines.append(rightTrimmed(cells.joined(separator: "  ")))
        }
        return lines.joined(separator: "\n")
    }

    static func assemble(
        tableName: String,
        columnHeaders: [String], columnRows: [[String]],
        indexHeaders: [String], indexRows: [[String]],
        ddl: String
    ) -> String {
        """
        \(sectionHeader("Table: \(tableName)"))

        \(sectionHeader("Column Information"))

        \(textTable(headers: columnHeaders, rows: columnRows))

        \(sectionHeader("Index Information"))

        \(textTable(headers: indexHeaders, rows: indexRows))

        \(sectionHeader("DDL Information"))

        \(ddl)
        """
    }
}
