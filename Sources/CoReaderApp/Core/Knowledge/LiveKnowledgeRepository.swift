import Foundation

extension KnowledgeRepository {
    static func liveDefault() throws -> KnowledgeRepository {
        let baseDirectory = try defaultBaseDirectory()
        return try KnowledgeRepository(
            markdownStore: MarkdownKnowledgeStore(
                baseDirectory: baseDirectory.appending(path: "Notes", directoryHint: .isDirectory)
            ),
            index: SQLiteKnowledgeIndex(
                databaseURL: baseDirectory.appending(path: "knowledge.sqlite")
            )
        )
    }

    private static func defaultBaseDirectory() throws -> URL {
        guard let applicationSupportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw NSError(
                domain: "CoReader.KnowledgeRepository",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unable to resolve Application Support directory."]
            )
        }

        let directory = applicationSupportDirectory
            .appending(path: "CoReader", directoryHint: .isDirectory)
            .appending(path: "Brain", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
