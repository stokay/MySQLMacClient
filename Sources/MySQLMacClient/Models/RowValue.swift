import Foundation
import MySQLNIO

/// Native Swift representation of a `MySQLData` cell, used for display and
/// for detecting whether an edited cell actually changed.
enum RowValue: Equatable, Hashable {
    case null
    case int(Int64)
    case double(Double)
    case string(String)
    case date(Date)
    case blob(Data)

    /// MySQL DATETIME/TIMESTAMP has no timezone; MySQLNIO decodes/encodes it as GMT.
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    /// Text shown in the grid and used as the starting point for editing.
    /// Empty string is used for NULL so an emptied cell round-trips back to NULL.
    var displayString: String {
        switch self {
        case .null: return ""
        case .int(let value): return String(value)
        case .double(let value): return String(value)
        case .string(let value): return value
        case .date(let value): return Self.dateFormatter.string(from: value)
        case .blob(let value): return "<\(value.count) bytes>"
        }
    }

    init(mysqlData: MySQLData) {
        guard mysqlData.buffer != nil else {
            self = .null
            return
        }
        switch mysqlData.type {
        case .tiny, .short, .long, .longlong, .int24, .bit, .year:
            if let value = mysqlData.int64 {
                self = .int(value)
            } else {
                self = .string(mysqlData.string ?? "")
            }
        case .float, .double, .newdecimal, .decimal:
            if let value = mysqlData.double {
                self = .double(value)
            } else {
                self = .string(mysqlData.string ?? "")
            }
        case .date, .datetime, .timestamp, .time:
            if let value = mysqlData.date {
                self = .date(value)
            } else {
                self = .string(mysqlData.string ?? "")
            }
        case .blob, .tinyBlob, .mediumBlob, .longBlob:
            if let buffer = mysqlData.buffer {
                self = .blob(Data(buffer.readableBytesView))
            } else {
                self = .null
            }
        default:
            self = .string(mysqlData.string ?? "")
        }
    }
}
