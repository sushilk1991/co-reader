import Foundation

struct ReadingStateStore {
    let fileURL: URL

    static func live() throws -> ReadingStateStore {
        let syncedDir = try CoReaderPaths.syncedDataDirectory
        return ReadingStateStore(
            fileURL: syncedDir.appending(path: "ReadingState.json")
        )
    }

    func load() throws -> ReadingState {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return ReadingState(documentURLs: [], activeDocumentURL: nil, positions: [:])
        }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        return try decoder.decode(ReadingState.self, from: data)
    }

    func save(_ state: ReadingState) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: .atomic)
    }
}
