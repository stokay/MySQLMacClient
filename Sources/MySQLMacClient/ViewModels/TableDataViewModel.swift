import Foundation
import MySQLNIO

/// Set when the query panel's last-run SQL was recognized as a simple,
/// single-table `SELECT` whose result includes every primary-key column of
/// that table — the minimum needed to build a safe `WHERE` clause for
/// editing. Its presence is what makes "Editable" in the query panel
/// actually do something instead of silently no-op-ing.
struct QueryEditContext {
    let database: String
    let table: String
    let primaryKeyColumns: [String]
    let columns: [ColumnInfo]
}

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

    // MARK: - Query panel

    @Published var isQueryPanelVisible = false
    @Published var queryText: String = ""
    /// One-shot: set by a sidebar double-click, consumed by `SQLTextView`
    /// (inserted at the cursor, then cleared back to `nil`).
    @Published var pendingQueryInsertion: String?
    /// Like `pendingQueryInsertion`, but appended to the end of the editor
    /// (after a blank line) and left selected — used by the sidebar's
    /// "SQL Sorgu Ekle" statement templates.
    @Published var pendingQueryAppend: String?
    @Published private(set) var isExecutingQuery = false
    @Published var queryErrorMessage: String?
    @Published private(set) var queryMessage: String?
    @Published private(set) var isShowingQueryResult = false
    @Published private(set) var queryResultColumns: [String] = []
    @Published private(set) var queryResultRows: [TableRow] = []
    @Published var isQueryResultEditableRequested = false
    @Published private(set) var queryEditContext: QueryEditContext?

    /// `true` once both the user asked for editing and the last query
    /// actually qualifies (single table, PK included in the result).
    var isQueryResultEditable: Bool { isQueryResultEditableRequested && queryEditContext != nil }

    /// Shown next to the Editable toggle when the user turned it on but the
    /// current result doesn't qualify, so the toggle doesn't look broken.
    var queryResultEditabilityNote: String? {
        guard isShowingQueryResult, isQueryResultEditableRequested, queryEditContext == nil else { return nil }
        return "Bu sonuç düzenlenemez (tek tablo + sonuçta primary key sütunu gerekir)."
    }

    let databaseName: String
    let tableName: String
    private let service: MySQLService
    private let introspection: SchemaIntrospectionService
    private var primaryKeyColumns: [String] = []
    private let defaultSelectLimit: Int

    /// `pageSize`/`defaultSelectLimit` default to the persisted settings;
    /// tests pass explicit values and never touch the singleton.
    init(
        databaseName: String,
        tableName: String,
        service: MySQLService,
        introspection: SchemaIntrospectionService,
        pageSize: Int? = nil,
        defaultSelectLimit: Int? = nil
    ) {
        self.databaseName = databaseName
        self.tableName = tableName
        self.service = service
        self.introspection = introspection
        // Resolve defaults here (inside @MainActor context) rather than as
        // default parameter values — Swift 6 strict concurrency forbids
        // referencing @MainActor-isolated properties in default parameters.
        self.pageSize = pageSize ?? SettingsStore.shared.settings.grid.defaultPageSize
        self.defaultSelectLimit = defaultSelectLimit ?? SettingsStore.shared.settings.editor.defaultSelectLimit
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

    /// Direction is driven by the caller rather than toggled in here —
    /// `SpreadsheetGridView` reads it off `NSTableColumn.sortDescriptorPrototype`,
    /// which AppKit already flips for same-column re-clicks and resets to
    /// ascending when a different column header is clicked.
    func applySort(column: String, ascending: Bool) async {
        sortColumn = column
        sortAscending = ascending
        currentOffset = 0
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
        let (whereSQL, whereBinds) = try primaryKeyWhereClause(for: row, primaryKeyColumns: primaryKeyColumns)
        let sql = "UPDATE \(try qualifiedTable()) SET \(setClauses.joined(separator: ", ")) WHERE \(whereSQL)"
        try await service.execute(sql, binds + whereBinds)
    }

    private func primaryKeyWhereClause(for row: TableRow, primaryKeyColumns: [String]) throws -> (sql: String, binds: [MySQLData]) {
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
            let (whereSQL, whereBinds) = try primaryKeyWhereClause(for: row, primaryKeyColumns: primaryKeyColumns)
            let sql = "DELETE FROM \(try qualifiedTable()) WHERE \(whereSQL)"
            try await service.execute(sql, whereBinds)
            await reload()
        } catch {
            errorMessage = describe(error)
        }
    }

    /// Inserts a row of DEFAULT/NULL values (skipping auto-increment columns)
    /// so the user can then edit cells in place, matching common SQL GUI UX.
    /// A NOT NULL column with no default (including a manually-assigned,
    /// non-auto-increment primary key — common on imported/legacy schemas)
    /// used to get `NULL` here regardless, which MySQL always rejects: the
    /// insert failed every time on that first, unavoidable NULL rather than
    /// on anything the user actually did. A type-appropriate placeholder
    /// (0 / '' / now()) lets the insert succeed instead, so the row exists
    /// and the user fixes the placeholder value via ordinary, already
    /// PK-aware cell editing — same as fixing any other value.
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
                } else if column.isNullable {
                    binds.append(.null)
                } else {
                    binds.append(placeholderValue(for: column))
                }
            }
            let sql = "INSERT INTO \(try qualifiedTable()) (\(columnNames.joined(separator: ", "))) VALUES (\(placeholders.joined(separator: ", ")))"
            try await service.execute(sql, binds)
            await reload()
        } catch {
            errorMessage = describe(error)
        }
    }

    /// A conservative type sniff off `SHOW COLUMNS`' `Type` string (e.g.
    /// `int(11)`, `varchar(255)`, `datetime`) — good enough to avoid an
    /// outright type-mismatch error, not a claim of picking a *meaningful*
    /// value. The user is expected to overwrite this immediately.
    private func placeholderValue(for column: ColumnInfo) -> MySQLData {
        let type = column.mysqlType.lowercased()
        if type.contains("int") || type.contains("decimal") || type.contains("float") || type.contains("double") {
            return MySQLData(string: "0")
        }
        if type.contains("date") || type.contains("time") {
            return MySQLData(string: RowValue.dateFormatter.string(from: Date()))
        }
        return MySQLData(string: "")
    }

    // MARK: - Table info ("İnfo" context-menu action)

    /// Non-nil replaces the grid with the plain-text info report; "Tablo
    /// Görünümüne Dön" sets it back to nil.
    @Published var tableInfoText: String?

    /// Builds the SQLyog-style text report (columns / indexes / DDL) for
    /// this table from `SHOW FULL COLUMNS`, `SHOW INDEX` and
    /// `SHOW CREATE TABLE`.
    func showTableInfo() async {
        do {
            let qualified = try qualifiedTable()
            let columnsResult = try await service.rawQuery("SHOW FULL COLUMNS FROM \(qualified)")
            let indexResult = try await service.rawQuery("SHOW INDEX FROM \(qualified)")
            let ddlResult = try await service.rawQuery("SHOW CREATE TABLE \(qualified)")

            let (columnHeaders, columnRows) = Self.tabulate(columnsResult.rows)
            let (indexHeaders, indexRows) = Self.tabulate(indexResult.rows)
            // Column 2 of SHOW CREATE TABLE ("Create Table") is the DDL.
            let ddl: String
            if let firstRow = ddlResult.rows.first, firstRow.columnDefinitions.count >= 2 {
                ddl = Self.reportString(firstRow.column(firstRow.columnDefinitions[1].name))
            } else {
                ddl = "(alınamadı)"
            }

            tableInfoText = TableInfoReport.assemble(
                tableName: tableName,
                columnHeaders: columnHeaders, columnRows: columnRows,
                indexHeaders: indexHeaders, indexRows: indexRows,
                ddl: ddl
            )
        } catch {
            tableInfoText = "Tablo bilgisi alınamadı: \(error.localizedDescription)"
        }
    }

    /// Result-set → ordered header names + stringified cells, preserving
    /// the server's own column order (`columnDefinitions`).
    private nonisolated static func tabulate(_ rows: [MySQLRow]) -> (headers: [String], rows: [[String]]) {
        guard let firstRow = rows.first else { return ([], []) }
        let headers = firstRow.columnDefinitions.map(\.name)
        let values = rows.map { row in
            headers.map { Self.reportString(row.column($0)) }
        }
        return (headers, values)
    }

    /// `(NULL)` for SQL NULL (the report shows it explicitly, unlike the
    /// grid); tries `.string` first because SHOW-command result columns
    /// often arrive typed as blobs that are really text.
    private nonisolated static func reportString(_ data: MySQLData?) -> String {
        guard let data, data.buffer != nil else { return "(NULL)" }
        if let string = data.string { return string }
        let value = RowValue(mysqlData: data)
        return value.isNull ? "(NULL)" : value.displayString
    }

    // MARK: - Query panel

    func toggleQueryPanel() {
        isQueryPanelVisible.toggle()
        if isQueryPanelVisible, queryText.isEmpty, let qualified = try? qualifiedTable() {
            queryText = "SELECT * FROM \(qualified) LIMIT \(defaultSelectLimit);"
        }
    }

    /// Live selection inside the SQL editor, kept up to date by
    /// `SQLTextView`'s coordinator. Deliberately *not* `@Published`: no view
    /// renders it, and publishing would re-invalidate the UI on every
    /// caret drag.
    var querySelectedText: String?

    /// Runs the editor's *selected* text when there is a selection, the
    /// whole editor otherwise (the SQLyog/DBeaver convention) — so part of
    /// a longer script can be executed by selecting just those lines.
    /// Results replace the editable table grid until `clearQueryResult()`.
    /// Whether they're actually *editable* depends on `resolveQueryEditContext`
    /// recognizing the query as a simple single-table SELECT — arbitrary SQL
    /// (joins, computed columns, aggregates) generally isn't safely mappable
    /// back to a row's primary key, so those stay read-only regardless of
    /// the Editable toggle.
    func runQuery() async {
        let selection = querySelectedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let sqlToRun = selection.isEmpty ? queryText : selection
        let trimmed = sqlToRun.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isExecutingQuery = true
        queryErrorMessage = nil
        queryMessage = nil
        defer { isExecutingQuery = false }
        do {
            let result = try await service.rawQuery(sqlToRun)
            if let firstRow = result.rows.first {
                let columnNames = firstRow.columnDefinitions.map(\.name)
                queryResultColumns = columnNames
                queryResultRows = result.rows.map { mysqlRow in
                    var values: [String: RowValue] = [:]
                    for definition in mysqlRow.columnDefinitions {
                        if let data = mysqlRow.column(definition.name) {
                            values[definition.name] = RowValue(mysqlData: data)
                        }
                    }
                    return TableRow(values: values)
                }
                isShowingQueryResult = true
                queryMessage = "\(result.rows.count) satır döndürüldü."
                await resolveQueryEditContext(executedSQL: sqlToRun, columnNames: columnNames)
            } else {
                queryResultColumns = []
                queryResultRows = []
                isShowingQueryResult = false
                queryEditContext = nil
                if let affected = result.affectedRows {
                    queryMessage = "\(affected) satır etkilendi."
                } else {
                    queryMessage = "Sorgu tamamlandı, sonuç yok."
                }
            }
        } catch {
            queryErrorMessage = describe(error)
            isShowingQueryResult = false
            queryEditContext = nil
        }
    }

    /// Also reloads the table grid — the query that was just showing
    /// results may well have been a write, so the grid we're switching back
    /// to shouldn't show stale pre-query data.
    func clearQueryResult() async {
        isShowingQueryResult = false
        queryResultColumns = []
        queryResultRows = []
        queryMessage = nil
        queryEditContext = nil
        await reload()
    }

    func commitQueryResultEdit(rowId: TableRow.ID, column: String, newText: String) async {
        guard let context = queryEditContext, isQueryResultEditableRequested,
              let index = queryResultRows.firstIndex(where: { $0.id == rowId }) else { return }
        queryResultRows[index].editedText[column] = newText
        guard queryResultRows[index].isDirty(column) else { return }

        do {
            try await updateQueryResultRow(queryResultRows[index], changedColumn: column, context: context)
            queryResultRows[index].acceptEdits(for: [column])
            queryErrorMessage = nil
        } catch {
            queryErrorMessage = describe(error)
        }
    }

    func deleteQueryResultRow(_ row: TableRow) async {
        guard let context = queryEditContext, isQueryResultEditableRequested else { return }
        do {
            let (whereSQL, whereBinds) = try primaryKeyWhereClause(for: row, primaryKeyColumns: context.primaryKeyColumns)
            let qualified = try SchemaIntrospectionService.qualifiedIdentifier(database: context.database, name: context.table)
            let sql = "DELETE FROM \(qualified) WHERE \(whereSQL)"
            try await service.execute(sql, whereBinds)
            await runQuery()
        } catch {
            queryErrorMessage = describe(error)
        }
    }

    private func updateQueryResultRow(_ row: TableRow, changedColumn: String, context: QueryEditContext) async throws {
        let qualified = try SchemaIntrospectionService.qualifiedIdentifier(database: context.database, name: context.table)
        let columnInfo = context.columns.first(where: { $0.name == changedColumn })
        let text = row.editedText[changedColumn] ?? ""
        let value: MySQLData = (text.isEmpty && (columnInfo?.isNullable ?? false)) ? .null : MySQLData(string: text)
        let setClause = "\(try quoted(changedColumn)) = ?"
        let (whereSQL, whereBinds) = try primaryKeyWhereClause(for: row, primaryKeyColumns: context.primaryKeyColumns)
        let sql = "UPDATE \(qualified) SET \(setClause) WHERE \(whereSQL)"
        try await service.execute(sql, [value] + whereBinds)
    }

    /// Deliberately conservative: only recognizes `SELECT ... FROM
    /// [\`db\`.]\`table\` [WHERE/ORDER/LIMIT ...]` with no JOIN/UNION/second
    /// table. False negatives just fall back to read-only (safe); this
    /// never needs to be a real SQL parser for that reason.
    private func detectSingleTableSelect(_ sql: String) -> (database: String, table: String)? {
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: #"^select\b"#, options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
        guard trimmed.range(of: #"\b(join|union)\b"#, options: [.regularExpression, .caseInsensitive]) == nil else { return nil }
        guard let fromRange = trimmed.range(of: #"\bfrom\b"#, options: [.regularExpression, .caseInsensitive]) else { return nil }

        let afterFrom = trimmed[fromRange.upperBound...]
        guard let identifierRange = afterFrom.range(
            of: #"^\s*(`[^`]+`|\w+)(\.(`[^`]+`|\w+))?"#,
            options: .regularExpression
        ) else { return nil }

        let remainder = afterFrom[identifierRange.upperBound...].trimmingCharacters(in: .whitespaces)
        guard !remainder.hasPrefix(",") else { return nil }

        let identifierText = afterFrom[identifierRange].trimmingCharacters(in: .whitespaces)
        let parts = identifierText.components(separatedBy: ".").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "`")) }
        switch parts.count {
        case 2: return (database: parts[0], table: parts[1])
        case 1: return (database: databaseName, table: parts[0])
        default: return nil
        }
    }

    private func resolveQueryEditContext(executedSQL: String, columnNames: [String]) async {
        queryEditContext = nil
        guard let detected = detectSingleTableSelect(executedSQL) else { return }
        do {
            let pkColumns = try await introspection.primaryKeyColumnNames(forTable: detected.table, inDatabase: detected.database)
            guard !pkColumns.isEmpty, Set(pkColumns).isSubset(of: Set(columnNames)) else { return }
            let tableColumns = try await introspection.columns(forTable: detected.table, inDatabase: detected.database)
            let relevantColumns = tableColumns.filter { columnNames.contains($0.name) }
            queryEditContext = QueryEditContext(
                database: detected.database,
                table: detected.table,
                primaryKeyColumns: pkColumns,
                columns: relevantColumns
            )
        } catch {
            queryEditContext = nil
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
