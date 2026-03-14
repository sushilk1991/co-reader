import Foundation

extension KnowledgeRepository {
    static func liveDefault() throws -> KnowledgeRepository {
        let syncedDir = try CoReaderPaths.syncedDataDirectory
        let localDir = try CoReaderPaths.localDataDirectory

        let notesDir = syncedDir.appending(path: "Notes", directoryHint: .isDirectory)
        let indexDir = localDir.appending(path: "Brain", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: indexDir, withIntermediateDirectories: true)

        return try KnowledgeRepository(
            markdownStore: MarkdownKnowledgeStore(baseDirectory: notesDir),
            index: SQLiteKnowledgeIndex(
                databaseURL: indexDir.appending(path: "knowledge.sqlite")
            )
        )
    }
}
