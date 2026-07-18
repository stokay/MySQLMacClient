import Foundation

struct ColumnInfo: Identifiable, Equatable, Hashable {
    var id: String { name }
    let name: String
    let mysqlType: String
    let isNullable: Bool
    let isPrimaryKey: Bool
    let isAutoIncrement: Bool
    let defaultValue: String?
    /// Column comment (from `SHOW FULL COLUMNS`). Defaulted so the many
    /// existing call sites that don't care about comments keep compiling.
    var comment: String? = nil
}
