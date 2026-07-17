import Foundation

enum CreateTableError: Error, LocalizedError {
    case emptyTableName
    case noColumns
    case invalidLength(column: String, value: String)

    var errorDescription: String? {
        switch self {
        case .emptyTableName:
            return "Tablo adı boş olamaz."
        case .noColumns:
            return "En az bir kolon eklemelisiniz."
        case .invalidLength(let column, let value):
            return "\"\(column)\" kolonunun uzunluğu geçersiz: \(value)"
        }
    }
}

/// Backs the "Yeni Tablo" form: a SQLyog-style column grid that's translated
/// into a single `CREATE TABLE` statement and executed against the chosen
/// database.
@MainActor
final class CreateTableViewModel: ObservableObject {
    struct DraftColumn: Identifiable {
        let id = UUID()
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
    }

    static let dataTypes = [
        "INT", "BIGINT", "SMALLINT", "TINYINT", "DECIMAL", "FLOAT", "DOUBLE",
        "VARCHAR", "CHAR", "TEXT", "MEDIUMTEXT", "LONGTEXT",
        "DATE", "DATETIME", "TIMESTAMP", "TIME", "BOOLEAN", "JSON", "BLOB",
    ]
    static let engines = ["[default]", "InnoDB", "MyISAM", "MEMORY", "ARCHIVE", "CSV"]

    @Published var tableName: String = ""
    @Published var database: String
    @Published var engine: String = "[default]"
    /// Reloads `collationOptions` for the newly picked charset — the two are
    /// server-defined pairs, not an independent cross product, so switching
    /// charset without refiltering would let the user pick a nonsense
    /// combination `CREATE TABLE` would reject.
    @Published var charset: String = "[default]" {
        didSet {
            guard charset != oldValue else { return }
            Task { await loadCollationOptions() }
        }
    }
    @Published var collation: String = "[default]"
    @Published var columns: [DraftColumn]

    /// Populated from the server (`SHOW CHARACTER SET`/`SHOW COLLATION`)
    /// rather than a hardcoded handful of names — real servers offer far
    /// more than any static list would cover.
    @Published private(set) var charsetOptions: [String] = ["[default]"]
    @Published private(set) var collationOptions: [String] = ["[default]"]

    @Published private(set) var isSubmitting = false
    @Published var errorMessage: String?

    /// Live `CREATE TABLE` text for the "SQL Önizleme" section — recomputed
    /// on every access (cheap: local string building, no I/O), so it always
    /// reflects the current form state without needing its own `@Published`
    /// wiring to every field it depends on.
    var previewSQL: String {
        (try? buildSQL()) ?? "-- Tablo adı ve en az bir kolon adı girildiğinde SQL burada görünecek --"
    }

    private let service: MySQLService
    private let introspection: SchemaIntrospectionService

    init(service: MySQLService, defaultDatabase: String) {
        self.service = service
        self.introspection = SchemaIntrospectionService(service: service)
        self.database = defaultDatabase
        self.columns = (0..<3).map { _ in DraftColumn() }
    }

    func loadCharsetOptions() async {
        if let sets = try? await introspection.characterSets() {
            charsetOptions = ["[default]"] + sets
        }
        await loadCollationOptions()
    }

    private func loadCollationOptions() async {
        let filterCharset = charset == "[default]" ? nil : charset
        guard let collations = try? await introspection.collations(forCharset: filterCharset) else { return }
        collationOptions = ["[default]"] + collations
        if !collationOptions.contains(collation) {
            collation = "[default]"
        }
    }

    var canSubmit: Bool {
        !tableName.trimmingCharacters(in: .whitespaces).isEmpty
            && !database.trimmingCharacters(in: .whitespaces).isEmpty
            && columns.contains { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
            && !isSubmitting
    }

    func addColumn() {
        columns.append(DraftColumn())
    }

    func removeColumn(_ id: UUID) {
        columns.removeAll { $0.id == id }
    }

    func moveColumn(id: UUID, direction: Int) {
        guard let index = columns.firstIndex(where: { $0.id == id }) else { return }
        let newIndex = index + direction
        guard columns.indices.contains(newIndex) else { return }
        columns.swapAt(index, newIndex)
    }

    /// Builds and runs the `CREATE TABLE` statement; returns the created
    /// table's info on success so the caller can refresh the sidebar and
    /// jump straight to it.
    func submit() async -> TableInfo? {
        errorMessage = nil
        let sql: String
        do {
            sql = try buildSQL()
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }

        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await service.execute(sql)
        } catch {
            errorMessage = "Tablo oluşturulamadı: \(error.localizedDescription)"
            return nil
        }

        return TableInfo(database: database, name: tableName.trimmingCharacters(in: .whitespaces), isView: false)
    }

    private func buildSQL() throws -> String {
        let trimmedName = tableName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { throw CreateTableError.emptyTableName }
        let qualifiedTable = try SchemaIntrospectionService.qualifiedIdentifier(database: database, name: trimmedName)

        let activeColumns = columns.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !activeColumns.isEmpty else { throw CreateTableError.noColumns }

        var columnClauses: [String] = []
        var primaryKeyColumns: [String] = []

        for column in activeColumns {
            let name = column.name.trimmingCharacters(in: .whitespaces)
            let quotedName = try SchemaIntrospectionService.quotedIdentifier(name)

            var clause = "\(quotedName) \(column.dataType)"

            if let length = try Self.validatedLength(column.length, columnName: name) {
                clause += "(\(length))"
            }
            if column.isUnsigned {
                clause += " UNSIGNED"
            }
            clause += (column.isPrimaryKey || column.isNotNull) ? " NOT NULL" : " NULL"
            if column.isAutoIncrement {
                clause += " AUTO_INCREMENT"
            }
            if let defaultClause = Self.defaultClause(for: column.defaultValue) {
                clause += " \(defaultClause)"
            }
            let trimmedComment = column.comment.trimmingCharacters(in: .whitespaces)
            if !trimmedComment.isEmpty {
                clause += " COMMENT '\(Self.escapeLiteral(trimmedComment))'"
            }

            columnClauses.append(clause)
            if column.isPrimaryKey {
                primaryKeyColumns.append(quotedName)
            }
        }

        if !primaryKeyColumns.isEmpty {
            columnClauses.append("PRIMARY KEY (\(primaryKeyColumns.joined(separator: ", ")))")
        }

        var sql = "CREATE TABLE \(qualifiedTable) (\n  \(columnClauses.joined(separator: ",\n  "))\n)"

        var tableOptions: [String] = []
        if engine != "[default]" { tableOptions.append("ENGINE=\(engine)") }
        if charset != "[default]" { tableOptions.append("DEFAULT CHARSET=\(charset)") }
        if collation != "[default]" { tableOptions.append("COLLATE=\(collation)") }
        if !tableOptions.isEmpty {
            sql += " " + tableOptions.joined(separator: " ")
        }

        return sql
    }

    /// The length field is spliced into the SQL unquoted (`VARCHAR(255)`,
    /// `DECIMAL(10,2)`) so — unlike names, which are backtick-escaped, and
    /// literals, which are quote-escaped — it must be restricted to digits
    /// and an optional comma up front, or a value like `10); DROP TABLE x;
    /// --` would inject arbitrary SQL straight into the statement.
    private static func validatedLength(_ raw: String, columnName: String) throws -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let isValid = trimmed.allSatisfy { $0.isNumber || $0 == "," } && trimmed.first != "," && trimmed.last != ","
        guard isValid else { throw CreateTableError.invalidLength(column: columnName, value: trimmed) }
        return trimmed
    }

    private static func defaultClause(for raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let upper = trimmed.uppercased()
        if upper == "NULL" || upper == "CURRENT_TIMESTAMP" || Double(trimmed) != nil {
            return "DEFAULT \(trimmed)"
        }
        return "DEFAULT '\(escapeLiteral(trimmed))'"
    }

    private static func escapeLiteral(_ raw: String) -> String {
        raw.replacingOccurrences(of: "'", with: "''")
    }
}
