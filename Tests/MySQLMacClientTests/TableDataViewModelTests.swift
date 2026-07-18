import XCTest
@testable import MySQLMacClient

/// Runs against a real local MariaDB/MySQL (XAMPP), not a mock — see
/// MySQLClient.md's validation plan. Each test resets the `widgets` seed
/// data in setUp and re-queries the database directly after ViewModel
/// mutations rather than trusting the optimistic in-memory state.
@MainActor
final class TableDataViewModelTests: XCTestCase {
    var service: MySQLService!
    var introspection: SchemaIntrospectionService!

    override func setUp() async throws {
        service = MySQLService()
        try await service.connect(
            host: "127.0.0.1",
            port: 3306,
            username: "root",
            password: nil,
            database: "mysqlmacclient_test"
        )
        introspection = SchemaIntrospectionService(service: service)
        try await resetWidgets()
    }

    override func tearDown() async throws {
        try await service.disconnect()
    }

    private func resetWidgets() async throws {
        try await service.execute("DELETE FROM widgets")
        try await service.execute("ALTER TABLE widgets AUTO_INCREMENT = 1")
        try await service.execute("""
            INSERT INTO widgets (name, quantity, created_at, notes) VALUES
            ('Bolt', 100, '2024-01-15 10:30:00', 'Standard bolt'),
            ('Nut', 250, '2024-02-20 14:00:00', NULL),
            ('Washer', NULL, NULL, 'Out of stock')
            """)
    }

    private func row(_ viewModel: TableDataViewModel, named name: String) -> TableRow? {
        viewModel.rows.first { $0.originalValues["name"]?.displayString == name }
    }

    func testLoadFetchesColumnsAndRows() async throws {
        let viewModel = TableDataViewModel(databaseName: "mysqlmacclient_test", tableName: "widgets", service: service, introspection: introspection)
        await viewModel.load()

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.hasPrimaryKey)
        XCTAssertEqual(viewModel.totalRowCount, 3)
        XCTAssertEqual(viewModel.rows.count, 3)
        XCTAssertEqual(viewModel.columns.map(\.name).sorted(), ["created_at", "id", "name", "notes", "quantity"])
    }

    func testTableWithoutPrimaryKeyDisablesEditing() async throws {
        let viewModel = TableDataViewModel(databaseName: "mysqlmacclient_test", tableName: "widget_logs_nopk", service: service, introspection: introspection)
        await viewModel.load()

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.hasPrimaryKey)
    }

    func testCommitEditUpdatesOnlyTheChangedColumn() async throws {
        let viewModel = TableDataViewModel(databaseName: "mysqlmacclient_test", tableName: "widgets", service: service, introspection: introspection)
        await viewModel.load()
        guard let bolt = row(viewModel, named: "Bolt") else { return XCTFail("seed row missing") }

        await viewModel.commitEdit(rowId: bolt.id, column: "quantity", newText: "999")
        XCTAssertNil(viewModel.errorMessage)

        let rows = try await service.query("SELECT quantity, notes FROM widgets WHERE id = 1")
        XCTAssertEqual(rows.first?.column("quantity")?.int, 999)
        XCTAssertEqual(rows.first?.column("notes")?.string, "Standard bolt")
    }

    func testCommitEditEmptyTextOnNullableColumnWritesNull() async throws {
        let viewModel = TableDataViewModel(databaseName: "mysqlmacclient_test", tableName: "widgets", service: service, introspection: introspection)
        await viewModel.load()
        guard let nut = row(viewModel, named: "Nut") else { return XCTFail("seed row missing") }

        await viewModel.commitEdit(rowId: nut.id, column: "quantity", newText: "")
        XCTAssertNil(viewModel.errorMessage)

        let rows = try await service.query("SELECT quantity FROM widgets WHERE id = 2")
        XCTAssertNil(rows.first?.column("quantity")?.int)
    }

    func testDeleteRowRemovesFromDatabase() async throws {
        let viewModel = TableDataViewModel(databaseName: "mysqlmacclient_test", tableName: "widgets", service: service, introspection: introspection)
        await viewModel.load()
        guard let washer = row(viewModel, named: "Washer") else { return XCTFail("seed row missing") }

        await viewModel.deleteRow(washer)
        XCTAssertNil(viewModel.errorMessage)

        let rows = try await service.query("SELECT COUNT(*) AS cnt FROM widgets")
        XCTAssertEqual(rows.first?.column("cnt")?.int, 2)
    }

    func testInsertBlankRowAddsRowToDatabase() async throws {
        // `tags` has only an auto-increment PK and a nullable column, so a
        // blank insert (all NULL/DEFAULT) is guaranteed to succeed.
        try await service.execute("DELETE FROM tags")
        let viewModel = TableDataViewModel(databaseName: "mysqlmacclient_test", tableName: "tags", service: service, introspection: introspection)
        await viewModel.load()

        await viewModel.insertBlankRow()
        XCTAssertNil(viewModel.errorMessage)

        let rows = try await service.query("SELECT COUNT(*) AS cnt FROM tags")
        XCTAssertEqual(rows.first?.column("cnt")?.int, 1)
    }

    func testInsertBlankRowOnRequiredTextColumnUsesEmptyStringInsteadOfFailing() async throws {
        // `widgets.name` is NOT NULL with no default. Sending NULL for it
        // (the old behavior) made every blank insert fail immediately —
        // not because of anything the user did, just because the column is
        // required. An empty string is a valid VARCHAR NOT NULL value, so
        // the insert now succeeds and the user fixes the placeholder via
        // ordinary cell editing, same as any other value.
        let viewModel = TableDataViewModel(databaseName: "mysqlmacclient_test", tableName: "widgets", service: service, introspection: introspection)
        await viewModel.load()

        await viewModel.insertBlankRow()
        XCTAssertNil(viewModel.errorMessage)

        let rows = try await service.query("SELECT COUNT(*) AS cnt FROM widgets WHERE name = ''")
        XCTAssertEqual(rows.first?.column("cnt")?.int, 1)
    }

    func testInsertBlankRowOnTableWithManuallyAssignedPrimaryKeySucceeds() async throws {
        // A non-auto-increment PRIMARY KEY (common on imported/legacy
        // schemas) is itself NOT NULL with no default — this is exactly
        // the case the user hit: every blank insert failed with "Column
        // 'item_code' cannot be null" before the row even reached the
        // grid for editing.
        try await service.execute("DELETE FROM manual_pk_items")
        let viewModel = TableDataViewModel(databaseName: "mysqlmacclient_test", tableName: "manual_pk_items", service: service, introspection: introspection)
        await viewModel.load()

        await viewModel.insertBlankRow()
        XCTAssertNil(viewModel.errorMessage)

        let rows = try await service.query("SELECT item_code, label FROM manual_pk_items")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.column("item_code")?.int, 0)
        XCTAssertEqual(rows.first?.column("label")?.string, "")
    }

    func testPaginationLimitsRowsPerPage() async throws {
        let viewModel = TableDataViewModel(databaseName: "mysqlmacclient_test", tableName: "widgets", service: service, introspection: introspection)
        await viewModel.load()
        await viewModel.changePageSize(2)

        XCTAssertEqual(viewModel.rows.count, 2)
        XCTAssertEqual(viewModel.totalRowCount, 3)

        await viewModel.nextPage()
        XCTAssertEqual(viewModel.rows.count, 1)
    }

    func testFilterNarrowsRows() async throws {
        let viewModel = TableDataViewModel(databaseName: "mysqlmacclient_test", tableName: "widgets", service: service, introspection: introspection)
        await viewModel.load()

        await viewModel.applyFilter(column: "name", value: "Bolt")
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.totalRowCount, 1)
        XCTAssertEqual(viewModel.rows.first?.originalValues["name"]?.displayString, "Bolt")
    }

    func testApplySortOrdersRowsAndTogglingFlipsDirection() async throws {
        let viewModel = TableDataViewModel(databaseName: "mysqlmacclient_test", tableName: "widgets", service: service, introspection: introspection)
        await viewModel.load()

        await viewModel.applySort(column: "name", ascending: true)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.rows.map { $0.originalValues["name"]?.displayString }, ["Bolt", "Nut", "Washer"])

        await viewModel.applySort(column: "name", ascending: false)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.rows.map { $0.originalValues["name"]?.displayString }, ["Washer", "Nut", "Bolt"])
    }

    func testRunQuerySelectShowsReadOnlyResultInPlaceOfTheGrid() async throws {
        let viewModel = TableDataViewModel(databaseName: "mysqlmacclient_test", tableName: "widgets", service: service, introspection: introspection)
        await viewModel.load()

        viewModel.queryText = "SELECT name FROM widgets WHERE quantity > 100"
        await viewModel.runQuery()

        XCTAssertNil(viewModel.queryErrorMessage)
        XCTAssertTrue(viewModel.isShowingQueryResult)
        XCTAssertEqual(viewModel.queryResultColumns, ["name"])
        XCTAssertEqual(viewModel.queryResultRows.map { $0.originalValues["name"]?.displayString }, ["Nut"])
    }

    func testRunQueryExecutesOnlySelectionWhenOneExists() async throws {
        let viewModel = TableDataViewModel(databaseName: "mysqlmacclient_test", tableName: "widgets", service: service, introspection: introspection)
        await viewModel.load()

        // The full editor holds a destructive UPDATE; the selection is a
        // harmless SELECT. Only the selection may run.
        viewModel.queryText = "UPDATE widgets SET quantity = 42 WHERE name = 'Bolt'"
        viewModel.querySelectedText = "SELECT name FROM widgets WHERE name = 'Nut'"
        await viewModel.runQuery()

        XCTAssertNil(viewModel.queryErrorMessage)
        XCTAssertEqual(viewModel.queryResultColumns, ["name"])
        XCTAssertEqual(viewModel.queryResultRows.map { $0.originalValues["name"]?.displayString }, ["Nut"])

        let rows = try await service.query("SELECT quantity FROM widgets WHERE name = 'Bolt'")
        XCTAssertEqual(rows.first?.column("quantity")?.int, 100, "editördeki UPDATE çalışmamalıydı")
    }

    func testRunQueryFallsBackToFullTextWhenSelectionIsEmpty() async throws {
        let viewModel = TableDataViewModel(databaseName: "mysqlmacclient_test", tableName: "widgets", service: service, introspection: introspection)
        await viewModel.load()

        viewModel.queryText = "SELECT name FROM widgets WHERE quantity > 100"
        viewModel.querySelectedText = "   "
        await viewModel.runQuery()

        XCTAssertNil(viewModel.queryErrorMessage)
        XCTAssertEqual(viewModel.queryResultRows.map { $0.originalValues["name"]?.displayString }, ["Nut"])
    }

    func testExplicitPageSizeAndSelectLimitOverridesFlowThrough() async throws {
        let viewModel = TableDataViewModel(
            databaseName: "mysqlmacclient_test",
            tableName: "widgets",
            service: service,
            introspection: introspection,
            pageSize: 2,
            defaultSelectLimit: 77
        )
        await viewModel.load()

        XCTAssertEqual(viewModel.rows.count, 2, "pageSize LIMIT cümlesine yansımalı")
        XCTAssertEqual(viewModel.totalRowCount, 3)

        viewModel.toggleQueryPanel()
        XCTAssertTrue(viewModel.queryText.contains("LIMIT 77;"), "varsayılan sorgu şablonu ayarı kullanmalı: \(viewModel.queryText)")
    }

    func testShowTableInfoBuildsTextReportFromLiveSchema() async throws {
        let viewModel = TableDataViewModel(databaseName: "mysqlmacclient_test", tableName: "widgets", service: service, introspection: introspection)
        await viewModel.load()

        await viewModel.showTableInfo()

        let report = try XCTUnwrap(viewModel.tableInfoText)
        XCTAssertTrue(report.contains("/*Table: widgets*/"))
        XCTAssertTrue(report.contains("/*Column Information*/"))
        XCTAssertTrue(report.contains("Field"), "SHOW FULL COLUMNS başlıkları görünmeli")
        XCTAssertTrue(report.contains("id"))
        XCTAssertTrue(report.contains("/*Index Information*/"))
        XCTAssertTrue(report.contains("PRIMARY"))
        XCTAssertTrue(report.contains("/*DDL Information*/"))
        XCTAssertTrue(report.contains("CREATE TABLE"))
    }

    func testRunQueryUpdateShowsAffectedRowMessageAndAppliesTheWrite() async throws {
        let viewModel = TableDataViewModel(databaseName: "mysqlmacclient_test", tableName: "widgets", service: service, introspection: introspection)
        await viewModel.load()

        viewModel.queryText = "UPDATE widgets SET quantity = 42 WHERE name = 'Bolt'"
        await viewModel.runQuery()

        XCTAssertNil(viewModel.queryErrorMessage)
        XCTAssertFalse(viewModel.isShowingQueryResult)
        XCTAssertEqual(viewModel.queryMessage, "1 satır etkilendi.")

        let rows = try await service.query("SELECT quantity FROM widgets WHERE name = 'Bolt'")
        XCTAssertEqual(rows.first?.column("quantity")?.int, 42)
    }

    func testRunQueryBadSqlSurfacesErrorWithoutCrashing() async throws {
        let viewModel = TableDataViewModel(databaseName: "mysqlmacclient_test", tableName: "widgets", service: service, introspection: introspection)
        await viewModel.load()

        viewModel.queryText = "SELEKT * FROM widgets"
        await viewModel.runQuery()

        XCTAssertNotNil(viewModel.queryErrorMessage)
        XCTAssertFalse(viewModel.isShowingQueryResult)
    }

    func testClearQueryResultReturnsToTableGridAndReloadsIt() async throws {
        let viewModel = TableDataViewModel(databaseName: "mysqlmacclient_test", tableName: "widgets", service: service, introspection: introspection)
        await viewModel.load()

        viewModel.queryText = "UPDATE widgets SET quantity = 7 WHERE name = 'Nut'"
        await viewModel.runQuery()
        XCTAssertNil(viewModel.queryErrorMessage)

        await viewModel.clearQueryResult()

        XCTAssertFalse(viewModel.isShowingQueryResult)
        XCTAssertEqual(viewModel.rows.first { $0.originalValues["name"]?.displayString == "Nut" }?.originalValues["quantity"]?.displayString, "7")
    }

    func testSimpleSingleTableSelectWithPrimaryKeyBecomesEditable() async throws {
        let viewModel = TableDataViewModel(databaseName: "mysqlmacclient_test", tableName: "widgets", service: service, introspection: introspection)
        await viewModel.load()
        viewModel.isQueryResultEditableRequested = true

        viewModel.queryText = "SELECT id, name, quantity FROM widgets WHERE name = 'Bolt'"
        await viewModel.runQuery()

        XCTAssertNil(viewModel.queryErrorMessage)
        XCTAssertNotNil(viewModel.queryEditContext)
        XCTAssertTrue(viewModel.isQueryResultEditable)
        XCTAssertNil(viewModel.queryResultEditabilityNote)
    }

    func testQueryMissingPrimaryKeyColumnStaysReadOnlyEvenWhenEditableRequested() async throws {
        let viewModel = TableDataViewModel(databaseName: "mysqlmacclient_test", tableName: "widgets", service: service, introspection: introspection)
        await viewModel.load()
        viewModel.isQueryResultEditableRequested = true

        // No `id` column selected, so there's nothing to build a WHERE from.
        viewModel.queryText = "SELECT name, quantity FROM widgets"
        await viewModel.runQuery()

        XCTAssertNil(viewModel.queryErrorMessage)
        XCTAssertNil(viewModel.queryEditContext)
        XCTAssertFalse(viewModel.isQueryResultEditable)
        XCTAssertNotNil(viewModel.queryResultEditabilityNote)
    }

    func testJoinQueryStaysReadOnlyEvenWhenEditableRequested() async throws {
        let viewModel = TableDataViewModel(databaseName: "mysqlmacclient_test", tableName: "widgets", service: service, introspection: introspection)
        await viewModel.load()
        viewModel.isQueryResultEditableRequested = true

        viewModel.queryText = """
            SELECT w.id, w.name, l.message FROM widgets w
            JOIN widget_logs_nopk l ON l.widget_id = w.id
            """
        await viewModel.runQuery()

        XCTAssertNil(viewModel.queryErrorMessage)
        XCTAssertNil(viewModel.queryEditContext)
        XCTAssertFalse(viewModel.isQueryResultEditable)
    }

    func testCommitQueryResultEditUpdatesOnlyTheChangedColumnInTheDatabase() async throws {
        let viewModel = TableDataViewModel(databaseName: "mysqlmacclient_test", tableName: "widgets", service: service, introspection: introspection)
        await viewModel.load()
        viewModel.isQueryResultEditableRequested = true

        viewModel.queryText = "SELECT id, name, quantity, notes FROM widgets WHERE name = 'Bolt'"
        await viewModel.runQuery()
        guard let row = viewModel.queryResultRows.first else { return XCTFail("expected a result row") }

        await viewModel.commitQueryResultEdit(rowId: row.id, column: "quantity", newText: "321")
        XCTAssertNil(viewModel.queryErrorMessage)

        let check = try await service.query("SELECT quantity, notes FROM widgets WHERE id = 1")
        XCTAssertEqual(check.first?.column("quantity")?.int, 321)
        XCTAssertEqual(check.first?.column("notes")?.string, "Standard bolt")
    }

    func testDeleteQueryResultRowRemovesFromDatabaseAndRefreshesResults() async throws {
        let viewModel = TableDataViewModel(databaseName: "mysqlmacclient_test", tableName: "widgets", service: service, introspection: introspection)
        await viewModel.load()
        viewModel.isQueryResultEditableRequested = true

        viewModel.queryText = "SELECT id, name FROM widgets"
        await viewModel.runQuery()
        guard let washer = viewModel.queryResultRows.first(where: { $0.originalValues["name"]?.displayString == "Washer" }) else {
            return XCTFail("expected seed row missing")
        }

        await viewModel.deleteQueryResultRow(washer)
        XCTAssertNil(viewModel.queryErrorMessage)

        let check = try await service.query("SELECT COUNT(*) AS cnt FROM widgets")
        XCTAssertEqual(check.first?.column("cnt")?.int, 2)
        XCTAssertFalse(viewModel.queryResultRows.contains { $0.originalValues["name"]?.displayString == "Washer" })
    }

    func testEditableToggleOffMakesQueryResultReadOnlyEvenWithAQualifyingQuery() async throws {
        let viewModel = TableDataViewModel(databaseName: "mysqlmacclient_test", tableName: "widgets", service: service, introspection: introspection)
        await viewModel.load()
        viewModel.isQueryResultEditableRequested = false

        viewModel.queryText = "SELECT id, name FROM widgets"
        await viewModel.runQuery()

        XCTAssertNotNil(viewModel.queryEditContext, "the query itself still qualifies")
        XCTAssertFalse(viewModel.isQueryResultEditable, "but editing wasn't requested")
    }
}
