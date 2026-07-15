import Foundation
import MySQLNIO

@MainActor
final class TableDataViewModel: ObservableObject {
    @Published private(set) var columns: [ColumnInfo] = []
    @Published private(set) var rows: [TableRow] = []
    @Published var pageSize: Int = 1000
    @Published private(set) var currentOffset: Int = 0
    @Published private(set) var totalRowCount: Int = 0
    @Published var sortColumn: String?
    @Published var sortAscending: Bool = true
    @Published var filterColumn: String?
    @Published var filterValue: String = ""
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var hasPrimaryKey = true

    let databaseName: String
    let tableName: String
    private let service: MySQLService
    private let introspection: SchemaIntrospectionService
    private var primaryKeyColumns: [String] = []

    init(databaseName: String, tableName: String, service: MySQLService, introspection: SchemaIntrospectionService) {
        self.databaseName = databaseName
        self.tableName = tableName
        self.service = service
        self.introspection = introspection
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            columns = try await introspection.columns(forTable: tableName, inDatabase: databaseName)
            primaryKeyColumns = columns.filter(\.isPrimaryKey).map(\.name)
            hasPrimaryKey = !primaryKeyColumns.isEmpty
            currentOffset = 0
            try await reloadOrThrow()
        } catch {
            errorMessage = describe(error)
        }
    }

    func reload() async {
        errorMessage = nil
        do {
            try await reloadOrThrow()
        } catch {
            errorMessage = describe(error)
        }
    }

    private func reloadOrThrow() async throws {
        totalRowCount = try await fetchTotalCount()
        rows = try await fetchPage()
    }

    // MARK: - Fetching

    private func fetchTotalCount() async throws -> Int {
        var sql = "SELECT COUNT(*) AS cnt FROM \(try qualifiedTable())"
        var binds: [MySQLData] = []
        if let clause = try whereClause() {
            sql += " WHERE \(clause.sql)"
            binds = clause.binds
        }
        let result = try await service.query(sql, binds)
        return result.first?.column("cnt")?.int ?? 0
    }

    private func fetchPage() async throws -> [TableRow] {
        var sql = "SELECT * FROM \(try qualifiedTable())"
        var binds: [MySQLData] = []
        if let clause = try whereClause() {
            sql += " WHERE \(clause.sql)"
            binds = clause.binds
        }
        if let sortColumn, columns.contains(where: { $0.name == sortColumn }) {
            sql += " ORDER BY \(try quoted(sortColumn)) \(sortAscending ? "ASC" : "DESC")"
        }
        sql += " LIMIT \(pageSize) OFFSET \(currentOffset)"

        let mysqlRows = try await service.query(sql, binds)
        return mysqlRows.map { mysqlRow in
            var values: [String: RowValue] = [:]
            for definition in mysqlRow.columnDefinitions {
                if let data = mysqlRow.column(definition.name) {
                    values[definition.name] = RowValue(mysqlData: data)
                }
            }
            return TableRow(values: values)
        }
    }

    private func whereClause() throws -> (sql: String, binds: [MySQLData])? {
        guard let filterColumn, !filterValue.isEmpty,
              columns.contains(where: { $0.name == filterColumn }) else {
            return nil
        }
        let quotedColumn = try quoted(filterColumn)
        return ("\(quotedColumn) LIKE ?", [MySQLData(string: "%\(filterValue)%")])
    }

    func applyFilter(column: String?, value: String) async {
        filterColumn = column
        filterValue = value
        currentOffset = 0
        await reload()
    }

    func applySort(column: String) async {
        if sortColumn == column {
            sortAscending.toggle()
        } else {
            sortColumn = column
            sortAscending = true
        }
        await reload()
    }

    // MARK: - Pagination

    func nextPage() async {
        guard currentOffset + pageSize < totalRowCount else { return }
        currentOffset += pageSize
        await reload()
    }

    func previousPage() async {
        guard currentOffset > 0 else { return }
        currentOffset = max(0, currentOffset - pageSize)
        await reload()
    }

    func changePageSize(_ newSize: Int) async {
        guard newSize > 0, newSize != pageSize else { return }
        pageSize = newSize
        currentOffset = 0
        await reload()
    }

    // MARK: - Editing

    func commitEdit(rowId: TableRow.ID, column: String, newText: String) async {
        guard hasPrimaryKey, let index = rows.firstIndex(where: { $0.id == rowId }) else { return }
        rows[index].editedText[column] = newText
        guard rows[index].isDirty(column) else { return }

        do {
            try await updateRow(rows[index], changedColumns: [column])
            rows[index].acceptEdits(for: [column])
            errorMessage = nil
        } catch {
            errorMessage = describe(error)
        }
    }

    private func updateRow(_ row: TableRow, changedColumns: [String]) async throws {
        guard !changedColumns.isEmpty else { return }
        var setClauses: [String] = []
        var binds: [MySQLData] = []
        for column in changedColumns {
            setClauses.append("\(try quoted(column)) = ?")
            binds.append(bindValue(text: row.editedText[column] ?? "", column: column))
        }
        let (whereSQL, whereBinds) = try primaryKeyWhereClause(for: row)
        let sql = "UPDATE \(try qualifiedTable()) SET \(setClauses.joined(separator: ", ")) WHERE \(whereSQL)"
        try await service.execute(sql, binds + whereBinds)
    }

    private func primaryKeyWhereClause(for row: TableRow) throws -> (sql: String, binds: [MySQLData]) {
        var parts: [String] = []
        var binds: [MySQLData] = []
        for column in primaryKeyColumns {
            parts.append("\(try quoted(column)) = ?")
            binds.append(row.originalValues[column].map(mysqlData(for:)) ?? .null)
        }
        return (parts.joined(separator: " AND "), binds)
    }

    private func bindValue(text: String, column: String) -> MySQLData {
        guard let info = columns.first(where: { $0.name == column }) else {
            return MySQLData(string: text)
        }
        if text.isEmpty && info.isNullable {
            return .null
        }
        return MySQLData(string: text)
    }

    private func mysqlData(for value: RowValue) -> MySQLData {
        switch value {
        case .null: return .null
        case .int(let v): return MySQLData(string: String(v))
        case .double(let v): return MySQLData(string: String(v))
        case .string(let v): return MySQLData(string: v)
        case .date(let v): return MySQLData(string: RowValue.dateFormatter.string(from: v))
        case .blob(let v): return MySQLData(string: String(decoding: v, as: UTF8.self))
        }
    }

    func deleteRow(_ row: TableRow) async {
        guard hasPrimaryKey else { return }
        do {
            let (whereSQL, whereBinds) = try primaryKeyWhereClause(for: row)
            let sql = "DELETE FROM \(try qualifiedTable()) WHERE \(whereSQL)"
            try await service.execute(sql, whereBinds)
            await reload()
        } catch {
            errorMessage = describe(error)
        }
    }

    /// Inserts a row of NULL/DEFAULT values (skipping auto-increment columns)
    /// so the user can then edit cells in place, matching common SQL GUI UX.
    func insertBlankRow() async {
        guard hasPrimaryKey else { return }
        do {
            let insertable = columns.filter { !$0.isAutoIncrement }
            guard !insertable.isEmpty else { return }
            var columnNames: [String] = []
            var placeholders: [String] = []
            var binds: [MySQLData] = []
            for column in insertable {
                columnNames.append(try quoted(column.name))
                placeholders.append("?")
                if let defaultValue = column.defaultValue {
                    binds.append(MySQLData(string: defaultValue))
                } else {
                    binds.append(.null)
                }
            }
            let sql = "INSERT INTO \(try qualifiedTable()) (\(columnNames.joined(separator: ", "))) VALUES (\(placeholders.joined(separator: ", ")))"
            try await service.execute(sql, binds)
            await reload()
        } catch {
            errorMessage = describe(error)
        }
    }

    // MARK: - Helpers

    private func quoted(_ identifier: String) throws -> String {
        try SchemaIntrospectionService.quotedIdentifier(identifier)
    }

    private func qualifiedTable() throws -> String {
        try SchemaIntrospectionService.qualifiedIdentifier(database: databaseName, name: tableName)
    }

    private func describe(_ error: Error) -> String {
        if let mysqlError = error as? MySQLError {
            return "\(mysqlError)"
        }
        return error.localizedDescription
    }
}
