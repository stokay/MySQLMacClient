import Foundation

struct ConnectionProfile: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var host: String
    var port: Int
    var username: String
    /// nil/empty means "no default database" — the sidebar then shows every
    /// database the user can see on the server (`SHOW DATABASES`).
    var database: String?

    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: Int = 3306,
        username: String,
        database: String?
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.database = database
    }
}
