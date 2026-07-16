import XCTest
@testable import MySQLMacClient

/// Runs against a real local MariaDB/MySQL (XAMPP), not a mock — see
/// MySQLClient.md's validation plan.
final class MySQLServiceRawQueryTests: XCTestCase {
    var service: MySQLService!

    override func setUp() async throws {
        service = MySQLService()
        try await service.connect(
            host: "127.0.0.1",
            port: 3306,
            username: "root",
            password: nil,
            database: "mysqlmacclient_test"
        )
    }

    override func tearDown() async throws {
        try await service.disconnect()
    }

    func testRawQuerySelectReturnsRowsAndNoAffectedCount() async throws {
        let result = try await service.rawQuery("SELECT name, quantity FROM widgets ORDER BY name ASC")
        XCTAssertEqual(result.rows.count, 3)
        XCTAssertEqual(result.rows.first?.column("name")?.string, "Bolt")
        XCTAssertNil(result.affectedRows, "a SELECT never produces an affected-row count")
    }

    func testRawQueryUpdateReturnsAffectedCountAndNoRows() async throws {
        let result = try await service.rawQuery("UPDATE widgets SET quantity = 500 WHERE name = 'Bolt'")
        XCTAssertTrue(result.rows.isEmpty)
        XCTAssertEqual(result.affectedRows, 1)

        let check = try await service.query("SELECT quantity FROM widgets WHERE name = 'Bolt'")
        XCTAssertEqual(check.first?.column("quantity")?.int, 500)
    }

    func testRawQuerySyntaxErrorThrows() async throws {
        do {
            _ = try await service.rawQuery("SELEKT * FROM widgets")
            XCTFail("expected a syntax error to be thrown")
        } catch {
            // Any thrown error is acceptable proof the bad SQL wasn't silently accepted.
        }
    }
}
