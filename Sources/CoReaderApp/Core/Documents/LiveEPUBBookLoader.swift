import Foundation

struct LiveEPUBBookLoader: EPUBBookLoading {
    // Bound archive extraction so a stalled ditto cannot hold a reader request forever.
    private static let extractionTimeout: Duration = .seconds(60)

    private let parser: EPUBPackageParser
    private let cacheDirectory: URL?
    private let commandRunner: any ShellCommandRunning

    init(
        parser: EPUBPackageParser = EPUBPackageParser(),
        cacheDirectory: URL? = nil,
        commandRunner: any ShellCommandRunning = ProcessCommandRunner()
    ) {
        self.parser = parser
        self.cacheDirectory = cacheDirectory
        self.commandRunner = commandRunner
    }

    /// Keep filesystem work on GCD and await the bounded process without blocking a pool thread.
    /// `prepare (GCD) -> ditto (async) -> parse (GCD)`; failures remove partial output.
    func loadBook(from fileURL: URL) async throws -> EPUBBook {
        let normalizedURL = fileURL.standardizedFileURL
        let prepared = try await BlockingWork.run { _ in
            try prepareBook(from: normalizedURL)
        }

        if let cached = prepared.cached {
            return cached
        }

        do {
            try await extractArchive(at: normalizedURL, to: prepared.destination)
            return try await BlockingWork.run { _ in
                try parser.makeBook(
                    extractedRootURL: prepared.destination,
                    fallbackTitle: normalizedURL.deletingPathExtension().lastPathComponent
                )
            }
        } catch {
            // Cleanup must outlive cancellation of the reader request, while still running on GCD.
            await Task.detached {
                try? await BlockingWork.run { _ in
                    try FileManager.default.removeItem(at: prepared.destination)
                }
            }.value
            throw error
        }
    }

    /// Reuse a valid cache; otherwise prepare an empty destination for extraction.
    private func prepareBook(from fileURL: URL) throws -> (destination: URL, cached: EPUBBook?) {
        let fileManager = FileManager.default
        let destination = try extractedRootURL(for: fileURL)
        if fileManager.fileExists(atPath: destination.path()) {
            do {
                let book = try parser.makeBook(
                    extractedRootURL: destination,
                    fallbackTitle: fileURL.deletingPathExtension().lastPathComponent
                )
                return (destination, book)
            } catch {
                try? fileManager.removeItem(at: destination)
            }
        }

        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        return (destination, nil)
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

    /// Use the same timeout and pipe-draining path as AI commands; show extraction errors in the reader.
    private func extractArchive(at archiveURL: URL, to destinationURL: URL) async throws {
        let result: ShellCommandResult
        do {
            result = try await commandRunner.run(ShellCommand(
                executable: "/usr/bin/ditto",
                arguments: ["-x", "-k", archiveURL.path, destinationURL.path],
                standardInput: nil,
                timeout: Self.extractionTimeout
            ))
        } catch let error as ShellCommandError {
            throw EPUBLoaderError.extractionFailed(error.localizedDescription)
        }

        guard result.exitCode == EXIT_SUCCESS else {
            let detail = [result.standardError, result.standardOutput]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
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
