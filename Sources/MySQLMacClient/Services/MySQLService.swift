import Foundation
import Logging
import MySQLNIO
import NIOCore
import NIOPosix

/// `MySQLQueryMetadata` (from MySQLNIO) isn't `Sendable`, so it can't cross
/// the actor boundary back to the caller — this is a Sendable stand-in
/// carrying just the two fields callers need.
struct ExecuteResult: Sendable {
    let affectedRows: UInt64
    let lastInsertID: UInt64?
}

enum MySQLServiceError: Error, LocalizedError {
    case notConnected
    case invalidIdentifier(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Veritabanına bağlı değil."
        case .invalidIdentifier(let identifier):
            return "Geçersiz tablo/sütun adı: \(identifier)"
        }
    }
}

/// Owns a single `MySQLConnection` and the `EventLoopGroup` it runs on.
/// No pooling in the MVP: one connection per app session, created on
/// `connect` and torn down on `disconnect`.
actor MySQLService {
    private var eventLoopGroup: MultiThreadedEventLoopGroup?
    private var connection: MySQLConnection?

    /// Kept so a dropped connection can be silently re-established — shared
    /// hosts (cPanel/remote MySQL) commonly kill idle TCP connections at the
    /// network/firewall level; the client only learns about it on the next
    /// write, as `MySQLError.closed`. A single long-lived connection with no
    /// pooling (the MVP's explicit tradeoff) needs this to stay usable
    /// across a normal session instead of erroring on every idle gap.
    private var lastCredentials: (host: String, port: Int, username: String, password: String?, database: String?)?

    private(set) var isConnected: Bool = false

    /// `database: nil` connects with no default schema selected — MySQL
    /// allows this, and the caller is then expected to browse
    /// `SHOW DATABASES` and qualify every query as `` `db`.`table` ``.
    func connect(host: String, port: Int, username: String, password: String?, database: String?) async throws {
        if connection != nil {
            try await disconnect()
        }

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let eventLoop = group.next()
        let address = try SocketAddress.makeAddressResolvingHost(host, port: port)

        do {
            let conn = try await MySQLConnection.connect(
                to: address,
                username: username,
                database: database ?? "",
                password: password,
                tlsConfiguration: nil,
                on: eventLoop
            ).get()
            self.eventLoopGroup = group
            self.connection = conn
            self.isConnected = true
            self.lastCredentials = (host, port, username, password, database)
        } catch {
            try? await group.shutdownGracefully()
            throw error
        }
    }

    func disconnect() async throws {
        lastCredentials = nil
        guard let conn = connection else { return }
        await acquire()
        defer { release() }
        connection = nil
        isConnected = false
        try? await conn.close().get()
        try await eventLoopGroup?.shutdownGracefully()
        eventLoopGroup = nil
    }

    func query(_ sql: String, _ binds: [MySQLData] = []) async throws -> [MySQLRow] {
        try await withRetryOnClosedConnection {
            try await self.withExclusiveConnectionAccess { conn in
                try await conn.query(sql, binds).get()
            }
        }
    }

    @discardableResult
    func execute(_ sql: String, _ binds: [MySQLData] = []) async throws -> ExecuteResult {
        try await withRetryOnClosedConnection {
            try await self.withExclusiveConnectionAccess { conn in
                let box = MetadataBox()
                _ = try await conn.query(sql, binds, onRow: { _ in }, onMetadata: { metadata in
                    box.affectedRows = metadata.affectedRows
                    box.lastInsertID = metadata.lastInsertID
                }).get()
                return ExecuteResult(affectedRows: box.affectedRows, lastInsertID: box.lastInsertID)
            }
        }
    }

    /// Retries exactly once, and only for a connection that's actually
    /// dead — never for query errors like bad SQL or a duplicate key, which
    /// would just fail identically (or worse, double-apply a write) on retry.
    private func withRetryOnClosedConnection<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch MySQLError.closed {
            guard let credentials = lastCredentials else { throw MySQLError.closed }
            try await connect(
                host: credentials.host,
                port: credentials.port,
                username: credentials.username,
                password: credentials.password,
                database: credentials.database
            )
            return try await operation()
        }
    }

    // MARK: - Serialization

    // MySQL's wire protocol has no pipelining: only one command may be in
    // flight on a connection at a time. Actors alone don't guarantee that —
    // a suspended `await` lets another call into the actor and, without this
    // gate, two views switching quickly would both send commands on the same
    // connection at once, desyncing the protocol and getting the connection
    // closed by the server. This FIFO gate makes each query/execute wait its
    // turn instead.
    private var isBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    private func acquire() async {
        if !isBusy {
            isBusy = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        if !waiters.isEmpty {
            waiters.removeFirst().resume()
        } else {
            isBusy = false
        }
    }

    private func withExclusiveConnectionAccess<T>(_ body: (MySQLConnection) async throws -> T) async throws -> T {
        guard let conn = connection else { throw MySQLServiceError.notConnected }
        await acquire()
        defer { release() }
        return try await body(conn)
    }

    private final class MetadataBox: @unchecked Sendable {
        var affectedRows: UInt64 = 0
        var lastInsertID: UInt64?
    }
}
