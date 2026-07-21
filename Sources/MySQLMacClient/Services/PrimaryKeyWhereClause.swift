import MySQLNIO

/// Builds `` `col1` = ? AND `col2` = ? `` (composite-key aware) against a
/// row's *original* values — shared by the main grid (`TableDataViewModel`)
/// and the SQL console's query-result grid (`SQLConsoleViewModel`), both of
/// which need to target exactly one row by its primary key for an
/// UPDATE/DELETE.
func primaryKeyWhereClause(for row: TableRow, primaryKeyColumns: [String]) throws -> (sql: String, binds: [MySQLData]) {
    var parts: [String] = []
    var binds: [MySQLData] = []
    for column in primaryKeyColumns {
        parts.append("\(try SchemaIntrospectionService.quotedIdentifier(column)) = ?")
        binds.append(row.originalValues[column].map(\.mysqlData) ?? .null)
    }
    return (parts.joined(separator: " AND "), binds)
}
