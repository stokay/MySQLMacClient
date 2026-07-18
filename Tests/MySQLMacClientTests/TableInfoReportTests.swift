import XCTest
@testable import MySQLMacClient

/// Pure string formatting — no database needed.
final class TableInfoReportTests: XCTestCase {
    func testSectionHeaderRuleMatchesTitleWidth() {
        XCTAssertEqual(
            TableInfoReport.sectionHeader("Column Information"),
            "/*Column Information*/\n----------------------"
        )
    }

    func testTextTableAlignsColumnsAndRightAlignsNumbers() {
        let table = TableInfoReport.textTable(
            headers: ["Field", "Cardinality"],
            rows: [
                ["ilce_id", "970"],
                ["il", "(NULL)"],
            ]
        )
        XCTAssertEqual(table, """
        Field    Cardinality
        -------  -----------
        ilce_id          970
        il       (NULL)
        """.trimmingCharacters(in: .newlines))
    }

    func testTextTableEmptyHeaders() {
        XCTAssertEqual(TableInfoReport.textTable(headers: [], rows: []), "")
    }

    func testAssembleContainsAllSections() {
        let report = TableInfoReport.assemble(
            tableName: "widgets",
            columnHeaders: ["Field"], columnRows: [["id"]],
            indexHeaders: ["Key_name"], indexRows: [["PRIMARY"]],
            ddl: "CREATE TABLE `widgets` (...)"
        )
        XCTAssertTrue(report.contains("/*Table: widgets*/"))
        XCTAssertTrue(report.contains("/*Column Information*/"))
        XCTAssertTrue(report.contains("/*Index Information*/"))
        XCTAssertTrue(report.contains("/*DDL Information*/"))
        XCTAssertTrue(report.contains("CREATE TABLE `widgets`"))
    }
}
