import Foundation

/// One editable row of the Create/Alter Table forms' column grid. Shared by
/// both: Create starts from blank drafts, Alter seeds them from the live
/// schema via `init(from:)` and uses `originalName` to tell renames and
/// redefinitions (`CHANGE COLUMN`) apart from brand-new columns (`ADD`).
struct DraftColumn: Identifiable {
    let id = UUID()
    /// The column's name as it exists on the server — nil for rows created
    /// in the form.
    var originalName: String? = nil
    var name: String = ""
    var dataType: String = "VARCHAR"
    var length: String = ""
    var defaultValue: String = ""
    var comment: String = ""
    var isUnsigned: Bool = false
    var isAutoIncrement: Bool = false
    var isNotNull: Bool = false
    // A primary key column is always NOT NULL in MySQL — forcing it here
    // keeps the checkbox honest instead of silently overriding it only
    // at SQL-generation time.
    var isPrimaryKey: Bool = false {
        didSet {
            if isPrimaryKey { isNotNull = true }
        }
    }

    init() {}

    init(from column: ColumnInfo) {
        let parsed = Self.parse(mysqlType: column.mysqlType)
        originalName = column.name
        name = column.name
        dataType = parsed.dataType
        length = parsed.length
        defaultValue = Self.normalizedDefault(column.defaultValue)
        comment = column.comment ?? ""
        isUnsigned = parsed.isUnsigned
        isAutoIncrement = column.isAutoIncrement
        isNotNull = !column.isNullable
        isPrimaryKey = column.isPrimaryKey
    }

    /// Splits a server type string like `int(11) unsigned`, `varchar(80)`
    /// or `decimal(10,2)` into the form's separate fields. The base type is
    /// uppercased to match the picker's fixed options; the parenthesized
    /// part keeps its original case (`enum('A','b')` values are data).
    static func parse(mysqlType raw: String) -> (dataType: String, length: String, isUnsigned: Bool) {
        let isUnsigned = raw.lowercased().contains("unsigned")
        var base = raw
        var length = ""
        if let open = raw.firstIndex(of: "("), let close = raw.lastIndex(of: ")"), open < close {
            length = String(raw[raw.index(after: open)..<close])
            base = String(raw[..<open])
        } else {
            base = raw.components(separatedBy: " ").first ?? raw
        }
        return (base.trimmingCharacters(in: .whitespaces).uppercased(), length, isUnsigned)
    }

    /// `SHOW COLUMNS`' Default column is dialect-messy: MariaDB (≥10.2)
    /// returns string defaults *with* their quotes (`'abc'`), no-default as
    /// the literal string `NULL`, and timestamp defaults as
    /// `current_timestamp()`. Normalize all of that to what the form's
    /// Varsayılan field expects (a bare value, empty for "no default") so a
    /// round-trip through the Alter form doesn't re-quote or re-emit them.
    static func normalizedDefault(_ raw: String?) -> String {
        guard var value = raw else { return "" }
        if value.count >= 2, value.hasPrefix("'"), value.hasSuffix("'") {
            value = String(value.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        } else if value.uppercased() == "NULL" {
            return ""
        }
        if value.lowercased().hasPrefix("current_timestamp") {
            return "CURRENT_TIMESTAMP"
        }
        return value
    }

    /// The full column definition as it appears after `ADD COLUMN`/
    /// `CHANGE COLUMN x` or inside `CREATE TABLE (...)` — everything except
    /// PRIMARY KEY, which both statements express separately.
    func sqlDefinition() throws -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let quotedName = try SchemaIntrospectionService.quotedIdentifier(trimmedName)

        var clause = "\(quotedName) \(dataType)"
        if let validated = try Self.validatedLength(length, columnName: trimmedName) {
            clause += "(\(validated))"
        }
        if isUnsigned {
            clause += " UNSIGNED"
        }
        clause += (isPrimaryKey || isNotNull) ? " NOT NULL" : " NULL"
        if isAutoIncrement {
            clause += " AUTO_INCREMENT"
        }
        if let defaultClause = Self.defaultClause(for: defaultValue) {
            clause += " \(defaultClause)"
        }
        let trimmedComment = comment.trimmingCharacters(in: .whitespaces)
        if !trimmedComment.isEmpty {
            clause += " COMMENT '\(Self.escapeLiteral(trimmedComment))'"
        }
        return clause
    }

    /// Definition-level equality, used by Alter to decide whether a kept
    /// column needs a `CHANGE COLUMN` at all. `isPrimaryKey` is deliberately
    /// excluded — PK membership changes travel as separate DROP/ADD PRIMARY
    /// KEY clauses, not as part of the column definition.
    func describesSameColumn(as other: DraftColumn) -> Bool {
        name.trimmingCharacters(in: .whitespaces) == other.name.trimmingCharacters(in: .whitespaces)
            && dataType == other.dataType
            && length.trimmingCharacters(in: .whitespaces) == other.length.trimmingCharacters(in: .whitespaces)
            && defaultValue.trimmingCharacters(in: .whitespaces) == other.defaultValue.trimmingCharacters(in: .whitespaces)
            && comment.trimmingCharacters(in: .whitespaces) == other.comment.trimmingCharacters(in: .whitespaces)
            && isUnsigned == other.isUnsigned
            && isAutoIncrement == other.isAutoIncrement
            && isNotNull == other.isNotNull
    }

    /// The length field is spliced into the SQL unquoted (`VARCHAR(255)`,
    /// `DECIMAL(10,2)`) so — unlike names, which are backtick-escaped, and
    /// literals, which are quote-escaped — it must be restricted to digits
    /// and an optional comma up front, or a value like `10); DROP TABLE x;
    /// --` would inject arbitrary SQL straight into the statement.
    static func validatedLength(_ raw: String, columnName: String) throws -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let isValid = trimmed.allSatisfy { $0.isNumber || $0 == "," } && trimmed.first != "," && trimmed.last != ","
        guard isValid else { throw CreateTableError.invalidLength(column: columnName, value: trimmed) }
        return trimmed
    }

    static func defaultClause(for raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let upper = trimmed.uppercased()
        if upper == "NULL" || upper == "CURRENT_TIMESTAMP" || Double(trimmed) != nil {
            return "DEFAULT \(trimmed)"
        }
        return "DEFAULT '\(escapeLiteral(trimmed))'"
    }

    static func escapeLiteral(_ raw: String) -> String {
        raw.replacingOccurrences(of: "'", with: "''")
    }
}
