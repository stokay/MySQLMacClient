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

    func testInsertBlankRowSurfacesErrorWithoutCorruptingTableWhenColumnIsRequired() async throws {
        // `widgets.name` is NOT NULL with no default, so a blank insert must
        // fail loudly (via errorMessage) rather than silently inserting a
        // half-valid row or crashing — see MySQLClient.md's "no crash, no
        // silent corruption" requirement.
        let viewModel = TableDataViewModel(databaseName: "mysqlmacclient_test", tableName: "widgets", service: service, introspection: introspection)
        await viewModel.load()

        await viewModel.insertBlankRow()
        XCTAssertNotNil(viewModel.errorMessage)

        let rows = try await service.query("SELECT COUNT(*) AS cnt FROM widgets")
        XCTAssertEqual(rows.first?.column("cnt")?.int, 3, "failed insert must not leave a partial row behind")
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
}
