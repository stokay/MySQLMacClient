import Foundation

struct TableInfo: Identifiable, Equatable, Hashable {
    var id: String { "\(database).\(name)" }
    let database: String
    let name: String
    let isView: Bool
}
