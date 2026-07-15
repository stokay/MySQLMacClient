import Foundation

struct IndexInfo: Identifiable, Equatable, Hashable {
    var id: String { name }
    let name: String
    /// Ordered by `Seq_in_index` — composite indexes list columns in key order.
    let columns: [String]
    let isUnique: Bool
    let indexType: String
}
