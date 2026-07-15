import Foundation

struct DatabaseInfo: Identifiable, Equatable, Hashable {
    var id: String { name }
    let name: String
}
