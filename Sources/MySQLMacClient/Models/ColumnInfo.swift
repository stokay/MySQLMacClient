import Foundation

struct ColumnInfo: Identifiable, Equatable, Hashable {
    var id: String { name }
    let name: String
    let mysqlType: String
    let isNullable: Bool
    let isPrimaryKey: Bool
    let isAutoIncrement: Bool
    let defaultValue: String?
}
