import XCTest
@testable import MySQLMacClient

/// Pure string-building — no database needed.
final class SQLTemplateCreateViewTests: XCTestCase {
    func testCreateViewMatchesTheRequestedSkeletonExactly() {
        let sql = SQLTemplate.createView(database: "cantokay_adres_tr", name: "test")
        let expected = [
            "CREATE",
            "    /*[ALGORITHM = {UNDEFINED | MERGE | TEMPTABLE}]",
            "    [DEFINER = { user | CURRENT_USER }]",
            "    [SQL SECURITY { DEFINER | INVOKER }]*/",
            "    VIEW `cantokay_adres_tr`.`test` ",
            "    AS",
            "(SELECT * FROM ...);",
        ].joined(separator: "\n")
        XCTAssertEqual(sql, expected)
    }

    func testCreateViewSubstitutesDatabaseAndNameOnly() {
        let sql = SQLTemplate.createView(database: "db1", name: "my_view")
        XCTAssertTrue(sql.contains("VIEW `db1`.`my_view` "))
        XCTAssertTrue(sql.hasPrefix("CREATE\n"))
        XCTAssertTrue(sql.hasSuffix("(SELECT * FROM ...);"))
    }

    func testCreateStoredProcedureMatchesTheRequestedSkeletonExactly() {
        let sql = SQLTemplate.createStoredProcedure(database: "cantokay_adres_tr", name: "test")
        let expected = [
            "DELIMITER $$",
            "",
            "CREATE",
            "    /*[DEFINER = { user | CURRENT_USER }]*/",
            "    PROCEDURE `cantokay_adres_tr`.`test`()",
            "    /*LANGUAGE SQL",
            "    | [NOT] DETERMINISTIC",
            "    | { CONTAINS SQL | NO SQL | READS SQL DATA | MODIFIES SQL DATA }",
            "    | SQL SECURITY { DEFINER | INVOKER }",
            "    | COMMENT 'string'*/",
            "    BEGIN",
            "",
            "    END$$",
            "",
            "DELIMITER ;",
        ].joined(separator: "\n")
        XCTAssertEqual(sql, expected)
    }

    func testCreateFunctionMatchesTheRequestedSkeletonExactly() {
        let sql = SQLTemplate.createFunction(database: "cantokay_adres_tr", name: "test")
        let expected = [
            "DELIMITER $$",
            "",
            "CREATE",
            "    /*[DEFINER = { user | CURRENT_USER }]*/",
            "    FUNCTION `cantokay_adres_tr`.`test`()",
            "    RETURNS TYPE",
            "    /*LANGUAGE SQL",
            "    | [NOT] DETERMINISTIC",
            "    | { CONTAINS SQL | NO SQL | READS SQL DATA | MODIFIES SQL DATA }",
            "    | SQL SECURITY { DEFINER | INVOKER }",
            "    | COMMENT 'string'*/",
            "    BEGIN",
            "",
            "    END$$",
            "",
            "DELIMITER ;",
        ].joined(separator: "\n")
        XCTAssertEqual(sql, expected)
    }

    func testCreateTriggerMatchesTheRequestedSkeletonExactly() {
        let sql = SQLTemplate.createTrigger(database: "cantokay_adres_tr", name: "test")
        let expected = [
            "DELIMITER $$",
            "",
            "CREATE",
            "    /*[DEFINER = { user | CURRENT_USER }]*/",
            "    TRIGGER `cantokay_adres_tr`.`test` BEFORE/AFTER INSERT/UPDATE/DELETE",
            "    ON `cantokay_adres_tr`.`<Table Name>`",
            "    FOR EACH ROW BEGIN",
            "",
            "    END$$",
            "",
            "DELIMITER ;",
        ].joined(separator: "\n")
        XCTAssertEqual(sql, expected)
    }

    func testCreateEventMatchesTheRequestedSkeletonExactly() {
        let sql = SQLTemplate.createEvent(database: "cantokay_adres_tr", name: "test")
        let expected = [
            "DELIMITER $$",
            "",
            "-- SET GLOBAL event_scheduler = ON$$     -- required for event to execute but not create    ",
            "",
            "CREATE\t/*[DEFINER = { user | CURRENT_USER }]*/\tEVENT `cantokay_adres_tr`.`test`",
            "",
            "ON SCHEDULE",
            "\t /* uncomment the example below you want to use */",
            "\t-- scheduleexample 1: run once",
            "\t   --  AT 'YYYY-MM-DD HH:MM.SS'/CURRENT_TIMESTAMP { + INTERVAL 1 [HOUR|MONTH|WEEK|DAY|MINUTE|...] }",
            "\t-- scheduleexample 2: run at intervals forever after creation",
            "\t   -- EVERY 1 [HOUR|MONTH|WEEK|DAY|MINUTE|...]",
            "\t-- scheduleexample 3: specified start time, end time and interval for execution",
            "\t   /*EVERY 1  [HOUR|MONTH|WEEK|DAY|MINUTE|...]",
            "\t   STARTS CURRENT_TIMESTAMP/'YYYY-MM-DD HH:MM.SS' { + INTERVAL 1[HOUR|MONTH|WEEK|DAY|MINUTE|...] }",
            "\t   ENDS CURRENT_TIMESTAMP/'YYYY-MM-DD HH:MM.SS' { + INTERVAL 1 [HOUR|MONTH|WEEK|DAY|MINUTE|...] } */",
            "/*[ON COMPLETION [NOT] PRESERVE]",
            "[ENABLE | DISABLE]",
            "[COMMENT 'comment']*/",
            "",
            "DO",
            "\tBEGIN",
            "\t    (sql_statements)",
            "\tEND$$",
            "",
            "DELIMITER ;",
        ].joined(separator: "\n")
        XCTAssertEqual(sql, expected)
    }
}
