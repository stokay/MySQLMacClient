import XCTest
@testable import MySQLMacClient

/// Pure string-building — no database needed. The expected outputs mirror
/// the SQLyog-style formatting the feature was specified with.
final class SQLTemplateTests: XCTestCase {
    private let columns = [
        ColumnInfo(name: "ilce_id", mysqlType: "int(11)", isNullable: false, isPrimaryKey: true, isAutoIncrement: true, defaultValue: nil),
        ColumnInfo(name: "ilce_adi", mysqlType: "varchar(100)", isNullable: false, isPrimaryKey: false, isAutoIncrement: false, defaultValue: nil),
        ColumnInfo(name: "il_id", mysqlType: "int(11)", isNullable: false, isPrimaryKey: false, isAutoIncrement: false, defaultValue: nil),
    ]

    func testInsertTemplate() {
        let sql = SQLTemplate.generate(.insert, database: "testdb", table: "ilceler", columns: columns)
        XCTAssertEqual(sql, """
        INSERT INTO `testdb`.`ilceler`
                    (`ilce_id`,
                     `ilce_adi`,
                     `il_id`)
        VALUES ('ilce_id',
                'ilce_adi',
                'il_id');
        """)
    }

    func testUpdateTemplate() {
        let sql = SQLTemplate.generate(.update, database: "testdb", table: "ilceler", columns: columns)
        XCTAssertEqual(sql, """
        UPDATE `testdb`.`ilceler`
        SET `ilce_id` = 'ilce_id',
          `ilce_adi` = 'ilce_adi',
          `il_id` = 'il_id'
        WHERE `ilce_id` = 'ilce_id';
        """)
    }

    func testDeleteTemplate() {
        let sql = SQLTemplate.generate(.delete, database: "testdb", table: "ilceler", columns: columns)
        XCTAssertEqual(sql, """
        DELETE
        FROM `testdb`.`ilceler`
        WHERE `ilce_id` = 'ilce_id';
        """)
    }

    func testSelectTemplate() {
        let sql = SQLTemplate.generate(.select, database: "testdb", table: "ilceler", columns: columns)
        XCTAssertEqual(sql, """
        SELECT
          `ilce_id`,
          `ilce_adi`,
          `il_id`
        FROM `testdb`.`ilceler`
        LIMIT 0, 1000;
        """)
    }

    func testWhereFallsBackToFirstColumnWithoutPrimaryKey() {
        let noPK = columns.map {
            ColumnInfo(name: $0.name, mysqlType: $0.mysqlType, isNullable: $0.isNullable, isPrimaryKey: false, isAutoIncrement: false, defaultValue: nil)
        }
        let sql = SQLTemplate.generate(.delete, database: "testdb", table: "ilceler", columns: noPK)
        XCTAssertTrue(sql.hasSuffix("WHERE `ilce_id` = 'ilce_id';"))
    }
}
