import Foundation

/// The four statement skeletons the sidebar's "SQL Sorgu Ekle" context menu
/// can append to the query editor. Pure string building — the caller
/// supplies the table's real columns, and every value slot is a
/// placeholder quoting the column's own name (SQLyog's convention), for
/// the user to overwrite.
enum SQLTemplate {
    enum Kind {
        case insert, update, delete, select
    }

    static func generate(_ kind: Kind, database: String, table: String, columns: [ColumnInfo]) -> String {
        let qualified = "`\(database)`.`\(table)`"
        let names = columns.map(\.name)
        // WHERE targets the primary key when the table has one; without
        // one the first column is still a better starting point than an
        // empty WHERE.
        let whereColumn = columns.first(where: \.isPrimaryKey)?.name ?? names.first ?? "id"
        let whereClause = "WHERE `\(whereColumn)` = '\(whereColumn)';"

        switch kind {
        case .insert:
            let columnList = names
                .map { "`\($0)`" }
                .joined(separator: ",\n             ")
            let valueList = names
                .map { "'\($0)'" }
                .joined(separator: ",\n        ")
            return """
            INSERT INTO \(qualified)
                        (\(columnList))
            VALUES (\(valueList));
            """

        case .update:
            let assignments = names
                .map { "`\($0)` = '\($0)'" }
                .joined(separator: ",\n  ")
            return """
            UPDATE \(qualified)
            SET \(assignments)
            \(whereClause)
            """

        case .delete:
            return """
            DELETE
            FROM \(qualified)
            \(whereClause)
            """

        case .select:
            let columnList = names
                .map { "`\($0)`" }
                .joined(separator: ",\n  ")
            return """
            SELECT
              \(columnList)
            FROM \(qualified)
            LIMIT 0, 1000;
            """
        }
    }

    /// The `CREATE VIEW` skeleton for the sidebar database menu's
    /// "Oluştur ▸ View..." action. Unlike `generate(_:database:table:columns:)`
    /// there's no existing table to read columns from — the view's `SELECT`
    /// is exactly what the user is creating the view *to define*, so only
    /// the parts of the statement that don't depend on it are filled in.
    /// Built with explicit lines (not a triple-quote literal) so the
    /// template's exact whitespace can't drift from source re-indentation.
    static func createView(database: String, name: String) -> String {
        [
            "CREATE",
            "    /*[ALGORITHM = {UNDEFINED | MERGE | TEMPTABLE}]",
            "    [DEFINER = { user | CURRENT_USER }]",
            "    [SQL SECURITY { DEFINER | INVOKER }]*/",
            "    VIEW `\(database)`.`\(name)` ",
            "    AS",
            "(SELECT * FROM ...);",
        ].joined(separator: "\n")
    }

    /// `DELIMITER $$ ... $$ DELIMITER ;` skeleton for the sidebar database
    /// menu's "Oluştur ▸ Stored Procedure..." action. The `DELIMITER`
    /// switch is required here (not optional, unlike a plain statement) —
    /// without it, the client would split the definition on the first `;`
    /// inside the body, cutting it off mid-procedure.
    static func createStoredProcedure(database: String, name: String) -> String {
        [
            "DELIMITER $$",
            "",
            "CREATE",
            "    /*[DEFINER = { user | CURRENT_USER }]*/",
            "    PROCEDURE `\(database)`.`\(name)`()",
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
    }

    /// Same shape as `createStoredProcedure`, plus the `RETURNS` clause a
    /// function requires.
    static func createFunction(database: String, name: String) -> String {
        [
            "DELIMITER $$",
            "",
            "CREATE",
            "    /*[DEFINER = { user | CURRENT_USER }]*/",
            "    FUNCTION `\(database)`.`\(name)`()",
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
    }

    /// `<Table Name>` is left as a literal placeholder (not substituted) —
    /// unlike a view/procedure/function, a trigger's whole reason to exist
    /// is a *specific* table, which isn't knowable from just "which
    /// database was this menu opened on" the way the others are.
    static func createTrigger(database: String, name: String) -> String {
        [
            "DELIMITER $$",
            "",
            "CREATE",
            "    /*[DEFINER = { user | CURRENT_USER }]*/",
            "    TRIGGER `\(database)`.`\(name)` BEFORE/AFTER INSERT/UPDATE/DELETE",
            "    ON `\(database)`.`<Table Name>`",
            "    FOR EACH ROW BEGIN",
            "",
            "    END$$",
            "",
            "DELIMITER ;",
        ].joined(separator: "\n")
    }

    /// Tab-indented to match the exact skeleton this was specified with —
    /// unlike the others' 4-space comment blocks, this one's schedule
    /// examples use tabs throughout.
    static func createEvent(database: String, name: String) -> String {
        [
            "DELIMITER $$",
            "",
            "-- SET GLOBAL event_scheduler = ON$$     -- required for event to execute but not create    ",
            "",
            "CREATE\t/*[DEFINER = { user | CURRENT_USER }]*/\tEVENT `\(database)`.`\(name)`",
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
    }
}
