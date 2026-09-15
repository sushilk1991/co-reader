import Foundation
import SQLite3

final class SQLiteKnowledgeIndex {
    private let databaseURL: URL
    private var database: OpaquePointer?

    init(databaseURL: URL) throws {
        self.databaseURL = databaseURL
        try openDatabase()
        try migrate()
    }

    deinit {
        sqlite3_close(database)
    }

    func upsert(note: KnowledgeNote, fileURL: URL) throws {
        let sql = """
        INSERT INTO notes (
            id,
            note_kind,
            title,
            source_identifier,
            created_at,
            file_path,
            excerpt,
            page_index,
            note_preview,
            search_blob
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            note_kind = excluded.note_kind,
            title = excluded.title,
            source_identifier = excluded.source_identifier,
            created_at = excluded.created_at,
            file_path = excluded.file_path,
            excerpt = excluded.excerpt,
            page_index = excluded.page_index,
            note_preview = excluded.note_preview,
            search_blob = excluded.search_blob;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw error(message: "Failed to prepare knowledge upsert.")
        }
        defer { sqlite3_finalize(statement) }

        try bind(note.id.uuidString.lowercased(), at: 1, to: statement)
        try bind(note.kind.rawValue, at: 2, to: statement)
        try bind(note.title, at: 3, to: statement)
        try bind(note.sourceIdentifier, at: 4, to: statement)
        sqlite3_bind_double(statement, 5, note.createdAt.timeIntervalSince1970)
        try bind(fileURL.path, at: 6, to: statement)
        try bind(note.highlightExcerpt, at: 7, to: statement)
        bind(note.pageIndex, at: 8, to: statement)
        try bind(note.notePreview, at: 9, to: statement)
        try bind(searchBlob(for: note), at: 10, to: statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw error(message: "Failed to execute knowledge upsert.")
        }
    }

    func search(matching query: String, limit: Int = 20) throws -> [KnowledgeNoteSummary] {
        let sql = """
        SELECT id, note_kind, title, source_identifier, created_at, file_path, excerpt, page_index, note_preview
        FROM notes
        WHERE lower(title) LIKE ? OR lower(search_blob) LIKE ?
        ORDER BY created_at DESC
        LIMIT ?;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw error(message: "Failed to prepare knowledge search.")
        }
        defer { sqlite3_finalize(statement) }

        let searchTerm = "%\(query.lowercased())%"
        try bind(searchTerm, at: 1, to: statement)
        try bind(searchTerm, at: 2, to: statement)
        sqlite3_bind_int(statement, 3, Int32(limit))

        return readSummaries(from: statement)
    }

    func notes(forSource sourceIdentifier: String, limit: Int = 20) throws -> [KnowledgeNoteSummary] {
        let sql = """
        SELECT id, note_kind, title, source_identifier, created_at, file_path, excerpt, page_index, note_preview
        FROM notes
        WHERE source_identifier = ?
        ORDER BY created_at DESC
        LIMIT ?;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw error(message: "Failed to prepare knowledge source lookup.")
        }
        defer { sqlite3_finalize(statement) }

        try bind(sourceIdentifier, at: 1, to: statement)
        sqlite3_bind_int(statement, 2, Int32(limit))

        return readSummaries(from: statement)
    }

    /// Every indexed note and the markdown path it was indexed from.
    func indexedFilePathsByNoteID() throws -> [UUID: String] {
        let sql = "SELECT id, file_path FROM notes;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw error(message: "Failed to prepare knowledge listing.")
        }
        defer { sqlite3_finalize(statement) }

        var paths: [UUID: String] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = UUID(uuidString: text(at: 0, from: statement)) else { continue }
            paths[id] = text(at: 1, from: statement)
        }

        return paths
    }

    private func readSummaries(from statement: OpaquePointer?) -> [KnowledgeNoteSummary] {
        var summaries: [KnowledgeNoteSummary] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let idText = text(at: 0, from: statement)
            guard let id = UUID(uuidString: idText) else { continue }
            guard let kind = KnowledgeNoteKind(rawValue: text(at: 1, from: statement)) else {
                continue
            }

            summaries.append(
                KnowledgeNoteSummary(
                    id: id,
                    kind: kind,
                    title: text(at: 2, from: statement),
                    sourceIdentifier: text(at: 3, from: statement),
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4)),
                    highlightExcerpt: optionalText(at: 6, from: statement),
                    pageIndex: optionalInt(at: 7, from: statement),
                    notePreview: optionalText(at: 8, from: statement),
                    fileURL: URL(fileURLWithPath: text(at: 5, from: statement))
                )
            )
        }

        return summaries
    }

    func delete(noteID: UUID) throws {
        let sql = "DELETE FROM notes WHERE id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw error(message: "Failed to prepare knowledge delete.")
        }
        defer { sqlite3_finalize(statement) }

        try bind(noteID.uuidString.lowercased(), at: 1, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw error(message: "Failed to execute knowledge delete.")
        }
    }

    private func openDatabase() throws {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK else {
            throw error(message: "Failed to open knowledge database.")
        }
    }

    private func migrate() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS notes (
            id TEXT PRIMARY KEY,
            note_kind TEXT NOT NULL DEFAULT 'note',
            title TEXT NOT NULL,
            source_identifier TEXT NOT NULL,
            created_at REAL NOT NULL,
            file_path TEXT NOT NULL,
            excerpt TEXT,
            page_index INTEGER,
            note_preview TEXT,
            search_blob TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS notes_created_at_idx ON notes(created_at DESC);
        """

        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw error(message: "Failed to migrate knowledge database.")
        }

        try ensureColumnExists("note_kind", definition: "TEXT NOT NULL DEFAULT 'note'")
        try ensureColumnExists("page_index", definition: "INTEGER")
        try ensureColumnExists("note_preview", definition: "TEXT")
    }

    private func searchBlob(for note: KnowledgeNote) -> String {
        ([note.title, note.sourceIdentifier, note.highlightExcerpt, note.notePreview] + note.bulletPoints)
            .compactMap { $0 }
            .joined(separator: "\n")
            .lowercased()
    }

    private func bind(_ value: String?, at index: Int32, to statement: OpaquePointer?) throws {
        if let value {
            guard sqlite3_bind_text(statement, index, value, -1, sqliteTransient) == SQLITE_OK else {
                throw error(message: "Failed to bind SQLite text value.")
            }
        } else {
            guard sqlite3_bind_null(statement, index) == SQLITE_OK else {
                throw error(message: "Failed to bind SQLite null value.")
            }
        }
    }

    private func text(at index: Int32, from statement: OpaquePointer?) -> String {
        guard let value = sqlite3_column_text(statement, index) else {
            return ""
        }
        return String(cString: value)
    }

    private func optionalText(at index: Int32, from statement: OpaquePointer?) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        return text(at: index, from: statement)
    }

    private func bind(_ value: Int?, at index: Int32, to statement: OpaquePointer?) {
        if let value {
            sqlite3_bind_int64(statement, index, sqlite3_int64(value))
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func optionalInt(at index: Int32, from statement: OpaquePointer?) -> Int? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }

        return Int(sqlite3_column_int64(statement, index))
    }

    private func ensureColumnExists(_ name: String, definition: String) throws {
        let existingColumns = try tableColumns(named: "notes")
        guard !existingColumns.contains(name) else {
            return
        }

        let sql = "ALTER TABLE notes ADD COLUMN \(name) \(definition);"
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw error(message: "Failed to add notes.\(name) column.")
        }
    }

    private func tableColumns(named tableName: String) throws -> Set<String> {
        let sql = "PRAGMA table_info(\(tableName));"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw error(message: "Failed to inspect table schema.")
        }
        defer { sqlite3_finalize(statement) }

        var columns: Set<String> = []
        while sqlite3_step(statement) == SQLITE_ROW {
            columns.insert(text(at: 1, from: statement))
        }

        return columns
    }

    private func error(message: String) -> NSError {
        let sqliteMessage = database.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "unknown"
        return NSError(
            domain: "CoReader.SQLiteKnowledgeIndex",
            code: Int(sqlite3_errcode(database)),
            userInfo: [NSLocalizedDescriptionKey: "\(message) \(sqliteMessage)"]
        )
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
