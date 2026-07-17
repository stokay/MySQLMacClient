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
}
