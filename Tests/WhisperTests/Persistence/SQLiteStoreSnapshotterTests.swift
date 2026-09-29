import Foundation
import SQLite3
import XCTest
@testable import Whisper

final class SQLiteStoreSnapshotterTests: XCTestCase {
    func testSnapshotStopsAtOverallDeadlineEvenWhenStepsKeepSucceeding() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "WhisperSQLiteSnapshotDeadline-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("source.store")
        let destinationURL = directory.appendingPathComponent("destination.store")
        let writer = try openDatabase(
            at: sourceURL,
            flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        )
        defer { sqlite3_close(writer) }
        try execute(
            """
            CREATE TABLE records (id INTEGER PRIMARY KEY, payload BLOB NOT NULL);
            BEGIN IMMEDIATE;
            WITH RECURSIVE counter(value) AS (
                SELECT 1
                UNION ALL
                SELECT value + 1 FROM counter WHERE value < 64
            )
            INSERT INTO records(payload) SELECT randomblob(1024) FROM counter;
            COMMIT;
            """,
            in: writer
        )

        var uptime: TimeInterval = 0
        var completedSteps = 0
        let snapshotter = SQLiteStoreSnapshotter(
            pagesPerStep: 1,
            timeout: 1,
            busyTimeoutMilliseconds: 0,
            afterStep: {
                completedSteps += 1
                uptime = 2
            },
            uptime: { uptime }
        )

        XCTAssertThrowsError(
            try snapshotter.snapshotStore(from: sourceURL, to: destinationURL)
        ) { error in
            XCTAssertEqual(error as? SQLiteStoreSnapshotError, .timedOut)
        }
        XCTAssertEqual(completedSteps, 1)
    }

    func testSnapshotRemainsConsistentWhenSourceWALCheckpointsDuringCopy() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "WhisperSQLiteSnapshot-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("source.store")
        let destinationURL = directory.appendingPathComponent("destination.store")
        let writer = try openDatabase(
            at: sourceURL,
            flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        )
        defer { sqlite3_close(writer) }
        try execute(
            """
            PRAGMA page_size = 512;
            PRAGMA journal_mode = WAL;
            PRAGMA wal_autocheckpoint = 0;
            CREATE TABLE records (id INTEGER PRIMARY KEY, payload BLOB NOT NULL);
            BEGIN IMMEDIATE;
            WITH RECURSIVE counter(value) AS (
                SELECT 1
                UNION ALL
                SELECT value + 1 FROM counter WHERE value < 512
            )
            INSERT INTO records(payload) SELECT randomblob(1024) FROM counter;
            COMMIT;
            """,
            in: writer
        )
        let originalCount = try scalarInteger("SELECT count(*) FROM records;", in: writer)
        XCTAssertEqual(originalCount, 512)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path + "-wal"))

        var didCheckpointDuringCopy = false
        let snapshotter = SQLiteStoreSnapshotter(pagesPerStep: 1, afterStep: {
            guard !didCheckpointDuringCopy else { return }
            didCheckpointDuringCopy = true
            try self.execute(
                "BEGIN IMMEDIATE; INSERT INTO records(payload) VALUES (randomblob(1024)); COMMIT;",
                in: writer
            )
            var logFrameCount: Int32 = 0
            var checkpointedFrameCount: Int32 = 0
            let result = sqlite3_wal_checkpoint_v2(
                writer,
                nil,
                SQLITE_CHECKPOINT_PASSIVE,
                &logFrameCount,
                &checkpointedFrameCount
            )
            XCTAssertEqual(result, SQLITE_OK)
        })

        try snapshotter.snapshotStore(from: sourceURL, to: destinationURL)

        XCTAssertTrue(didCheckpointDuringCopy)
        let snapshot = try openDatabase(
            at: destinationURL,
            flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        )
        defer { sqlite3_close(snapshot) }
        XCTAssertEqual(try scalarText("PRAGMA integrity_check;", in: snapshot), "ok")
        XCTAssertGreaterThanOrEqual(
            try scalarInteger("SELECT count(*) FROM records;", in: snapshot),
            originalCount
        )
    }

    private func openDatabase(at url: URL, flags: Int32) throws -> OpaquePointer {
        var database: OpaquePointer?
        let result = url.withUnsafeFileSystemRepresentation { path in
            sqlite3_open_v2(path, &database, flags, nil)
        }
        guard result == SQLITE_OK, let database else {
            if let database { sqlite3_close(database) }
            throw SQLiteTestError(code: result)
        }
        return database
    }

    private func execute(_ sql: String, in database: OpaquePointer) throws {
        let result = sqlite3_exec(database, sql, nil, nil, nil)
        guard result == SQLITE_OK else { throw SQLiteTestError(code: result) }
    }

    private func scalarInteger(_ sql: String, in database: OpaquePointer) throws -> Int {
        let statement = try prepare(sql, in: database)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw SQLiteTestError(code: sqlite3_errcode(database))
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func scalarText(_ sql: String, in database: OpaquePointer) throws -> String {
        let statement = try prepare(sql, in: database)
        defer { sqlite3_finalize(statement) }
        guard
            sqlite3_step(statement) == SQLITE_ROW,
            let value = sqlite3_column_text(statement, 0)
        else {
            throw SQLiteTestError(code: sqlite3_errcode(database))
        }
        return String(cString: value)
    }

    private func prepare(_ sql: String, in database: OpaquePointer) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else {
            throw SQLiteTestError(code: result)
        }
        return statement
    }
}

private struct SQLiteTestError: Error {
    let code: Int32
}
