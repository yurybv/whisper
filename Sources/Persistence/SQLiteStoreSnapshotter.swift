import Foundation
import SQLite3

struct SQLiteStoreSnapshotter {
    typealias AfterStep = () throws -> Void
    typealias Uptime = () -> TimeInterval

    private let pagesPerStep: Int32
    private let timeout: TimeInterval
    private let busyTimeoutMilliseconds: Int32
    private let afterStep: AfterStep
    private let uptime: Uptime

    init(
        pagesPerStep: Int32 = 256,
        timeout: TimeInterval = 5,
        busyTimeoutMilliseconds: Int32 = 25,
        afterStep: @escaping AfterStep = {},
        uptime: @escaping Uptime = { ProcessInfo.processInfo.systemUptime }
    ) {
        precondition(pagesPerStep > 0)
        precondition(timeout > 0)
        precondition(busyTimeoutMilliseconds >= 0)
        self.pagesPerStep = pagesPerStep
        self.timeout = timeout
        self.busyTimeoutMilliseconds = busyTimeoutMilliseconds
        self.afterStep = afterStep
        self.uptime = uptime
    }

    func snapshotStore(from sourceURL: URL, to destinationURL: URL) throws {
        let deadline = uptime() + timeout
        let source = try openDatabase(
            at: sourceURL,
            flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        )
        defer { sqlite3_close(source) }
        let destination = try openDatabase(
            at: destinationURL,
            flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        )
        defer { sqlite3_close(destination) }

        sqlite3_busy_timeout(source, busyTimeoutMilliseconds)
        sqlite3_busy_timeout(destination, busyTimeoutMilliseconds)
        guard let backup = sqlite3_backup_init(destination, "main", source, "main") else {
            throw SQLiteStoreSnapshotError.sqlite(code: sqlite3_errcode(destination))
        }

        var operationError: Error?
        var stepResult = SQLITE_OK
        while stepResult != SQLITE_DONE {
            guard uptime() < deadline else {
                operationError = SQLiteStoreSnapshotError.timedOut
                break
            }
            stepResult = sqlite3_backup_step(backup, pagesPerStep)
            switch stepResult {
            case SQLITE_OK:
                do {
                    try afterStep()
                } catch {
                    operationError = error
                }
            case SQLITE_BUSY, SQLITE_LOCKED:
                sqlite3_sleep(10)
            case SQLITE_DONE:
                break
            default:
                operationError = SQLiteStoreSnapshotError.sqlite(code: stepResult)
            }
            if operationError == nil, stepResult != SQLITE_DONE, uptime() >= deadline {
                operationError = SQLiteStoreSnapshotError.timedOut
            }
            if operationError != nil { break }
        }

        let finishResult = sqlite3_backup_finish(backup)
        if let operationError { throw operationError }
        guard stepResult == SQLITE_DONE, finishResult == SQLITE_OK else {
            throw SQLiteStoreSnapshotError.sqlite(
                code: finishResult == SQLITE_OK ? stepResult : finishResult
            )
        }
    }

    private func openDatabase(at url: URL, flags: Int32) throws -> OpaquePointer {
        var database: OpaquePointer?
        let result = url.withUnsafeFileSystemRepresentation { path in
            sqlite3_open_v2(path, &database, flags, nil)
        }
        guard result == SQLITE_OK, let database else {
            if let database { sqlite3_close(database) }
            throw SQLiteStoreSnapshotError.sqlite(code: result)
        }
        return database
    }
}

enum SQLiteStoreSnapshotError: Error, Equatable {
    case sqlite(code: Int32)
    case timedOut
}
