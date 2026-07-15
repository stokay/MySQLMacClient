import Foundation

@MainActor
final class ConnectionFormViewModel: ObservableObject {
    @Published var name: String = ""
    @Published var host: String = "127.0.0.1"
    @Published var port: String = "3306"
    @Published var username: String = "root"
    @Published var password: String = ""
    @Published var database: String = ""

    @Published private(set) var isConnecting = false
    @Published var errorMessage: String?

    private let connectionStore: ConnectionStore
    private let keychainService = KeychainService()

    init(connectionStore: ConnectionStore) {
        self.connectionStore = connectionStore
    }

    var canSubmit: Bool {
        !host.isEmpty && !username.isEmpty && Int(port) != nil && !isConnecting
    }

    func connect() async -> AppSession? {
        errorMessage = nil
        guard let portNumber = Int(port) else {
            errorMessage = "Port sayısal olmalı."
            return nil
        }

        isConnecting = true
        defer { isConnecting = false }

        let trimmedDatabase = database.trimmingCharacters(in: .whitespaces)
        let service = MySQLService()
        do {
            try await service.connect(
                host: host,
                port: portNumber,
                username: username,
                password: password.isEmpty ? nil : password,
                database: trimmedDatabase.isEmpty ? nil : trimmedDatabase
            )
        } catch {
            errorMessage = "Bağlanılamadı: \(error.localizedDescription)"
            return nil
        }

        let profile = ConnectionProfile(
            name: name.isEmpty ? "\(username)@\(host)" : name,
            host: host,
            port: portNumber,
            username: username,
            database: trimmedDatabase.isEmpty ? nil : trimmedDatabase
        )
        try? keychainService.savePassword(password, forConnectionId: profile.id)
        connectionStore.add(profile)

        return AppSession(
            profile: profile,
            mysqlService: service,
            introspectionService: SchemaIntrospectionService(service: service)
        )
    }

    /// Reconnect using a previously saved profile; password is read from the Keychain.
    func connect(using profile: ConnectionProfile) async -> AppSession? {
        errorMessage = nil
        isConnecting = true
        defer { isConnecting = false }

        let storedPassword: String?
        do {
            storedPassword = try keychainService.readPassword(forConnectionId: profile.id)
        } catch {
            errorMessage = "Keychain'den şifre okunamadı: \(error.localizedDescription)"
            return nil
        }

        let service = MySQLService()
        do {
            try await service.connect(
                host: profile.host,
                port: profile.port,
                username: profile.username,
                password: storedPassword,
                database: profile.database
            )
        } catch {
            errorMessage = "Bağlanılamadı: \(error.localizedDescription)"
            return nil
        }

        return AppSession(
            profile: profile,
            mysqlService: service,
            introspectionService: SchemaIntrospectionService(service: service)
        )
    }
}
