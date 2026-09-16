import Foundation

struct KnowledgeRepository {
    let markdownStore: MarkdownKnowledgeStore
    let index: SQLiteKnowledgeIndex

    init(markdownStore: MarkdownKnowledgeStore, index: SQLiteKnowledgeIndex) throws {
        self.markdownStore = markdownStore
        self.index = index
    }

    func save(note: KnowledgeNote) throws {
        let fileURL = try markdownStore.save(note: note)
        try index.upsert(note: note, fileURL: fileURL)
    }

    func noteFileURL(for note: KnowledgeNote) -> URL {
        markdownStore.noteFileURL(for: note)
    }

    func searchNotes(matching query: String, limit: Int = 20) throws -> [KnowledgeNoteSummary] {
        try index.search(matching: query, limit: limit)
    }

    func notes(forSource sourceIdentifier: String, limit: Int = 20) throws -> [KnowledgeNoteSummary] {
        try index.notes(forSource: sourceIdentifier, limit: limit)
    }

    func delete(noteID: UUID) throws {
        try markdownStore.delete(noteID: noteID)
        try index.delete(noteID: noteID)
    }

    /// The markdown files sync through iCloud; the SQLite index does not. On a
    /// second Mac, or after the index is lost, this makes the synced notes
    /// searchable again and drops rows whose file has gone.
    ///
    /// ```
    ///  Notes/*.md ──parse (GCD)──▶ [StoredKnowledgeNote]
    ///        │                           │ not indexed at that path ──▶ upsert
    ///  index rows ────────────────────── │ no file any more ──────────▶ delete
    /// ```
    @MainActor
    func rebuildIndexFromMarkdown() async throws -> Int {
        let markdownStore = markdownStore
        let storedNotes = try await BlockingWork.run(qos: .utility) { _ in
            try markdownStore.loadNotes()
        }
        let indexedPaths = try index.indexedFilePathsByNoteID()
        var changes = 0

        for stored in storedNotes where indexedPaths[stored.note.id] != stored.fileURL.path {
            try index.upsert(note: stored.note, fileURL: stored.fileURL)
            changes += 1
        }

        // On macOS 15 an evicted iCloud note is a dataless file at its own path, so a
        // plain existence check is sufficient; no `.Name.md.icloud` sibling is produced.
        let storedIDs = Set(storedNotes.map(\.note.id))
        for (noteID, filePath) in indexedPaths
        where !storedIDs.contains(noteID) && !FileManager.default.fileExists(atPath: filePath) {
            try index.delete(noteID: noteID)
            changes += 1
        }

        return changes
    }
}
