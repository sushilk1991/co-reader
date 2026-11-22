import Foundation
@testable import CoreaderKit

/// A throwaway directory, removed when the value goes away. Tests never touch the real
/// library, caches, config or home folder.
final class TempDirectory: Sendable {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("coreader-tests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func file(_ name: String, _ contents: String) -> URL {
        let file = url.appendingPathComponent(name)
        try! FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! Data(contents.utf8).write(to: file)
        return file
    }
}

/// Whole-second dates: the library stores dates to the second.
func date(_ iso: String) -> Date {
    ISODate.parse(iso)!
}

struct TestLibrary {
    let temp = TempDirectory()
    let store: LibraryStore

    init() {
        store = LibraryStore(root: temp.url.appendingPathComponent("Library", isDirectory: true))
    }

    /// Imports a small fake book. Different `contents` means a different file hash.
    @discardableResult
    func add(_ title: String, authors: [String] = [], ext: String = "epub", contents: String? = nil) throws -> BookEntry {
        let source = temp.file("inbox/\(UUID().uuidString).\(ext)", contents ?? "contents of \(title)")
        return try store.importFile(at: source, metadata: ImportMetadata(title: title, authors: authors))
    }
}
