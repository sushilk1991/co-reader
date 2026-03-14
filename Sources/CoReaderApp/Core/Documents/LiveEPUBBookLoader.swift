import Foundation

struct LiveEPUBBookLoader: EPUBBookLoading {
    private let parser: EPUBPackageParser
    private let cacheDirectory: URL?

    init(
        parser: EPUBPackageParser = EPUBPackageParser(),
        cacheDirectory: URL? = nil
    ) {
        self.parser = parser
        self.cacheDirectory = cacheDirectory
    }

    func loadBook(from fileURL: URL) throws -> EPUBBook {
        let fileManager = FileManager.default
        let normalizedURL = fileURL.standardizedFileURL
        let fallbackTitle = normalizedURL.deletingPathExtension().lastPathComponent
        let destination = try extractedRootURL(for: normalizedURL)

        if fileManager.fileExists(atPath: destination.path()) {
            do {
                return try parser.makeBook(extractedRootURL: destination, fallbackTitle: fallbackTitle)
            } catch {
                try? fileManager.removeItem(at: destination)
            }
        }

        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        do {
            try extractArchive(at: normalizedURL, to: destination)
            return try parser.makeBook(extractedRootURL: destination, fallbackTitle: fallbackTitle)
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
    }

    private func extractedRootURL(for fileURL: URL) throws -> URL {
        try cacheRootURL().appending(path: cacheKey(for: fileURL), directoryHint: .isDirectory)
    }

    private func cacheRootURL() throws -> URL {
        let fileManager = FileManager.default
        if let cacheDirectory {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            return cacheDirectory
        }

        guard let applicationSupportDirectory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw EPUBLoaderError.extractionFailed("Unable to resolve the EPUB cache directory.")
        }

        let directory = applicationSupportDirectory
            .appending(path: "CoReader", directoryHint: .isDirectory)
            .appending(path: "EPUBCache", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func extractArchive(at archiveURL: URL, to destinationURL: URL) throws {
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archiveURL.path, destinationURL.path]
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let detail = String(decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw EPUBLoaderError.extractionFailed(detail)
        }
    }

    private func cacheKey(for fileURL: URL) throws -> String {
        let values = try fileURL.resourceValues(forKeys: [
            .contentModificationDateKey,
            .fileSizeKey
        ])
        let fileSize = values.fileSize ?? 0
        let modifiedAt = Int(values.contentModificationDate?.timeIntervalSince1970 ?? 0)

        return "\(sanitized(fileURL.deletingPathExtension().lastPathComponent))-\(fileSize)-\(modifiedAt)"
    }

    private func sanitized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
