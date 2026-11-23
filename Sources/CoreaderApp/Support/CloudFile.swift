import Foundation

/// iCloud Drive may keep only a placeholder for a file to save disk space ("Optimise Mac
/// Storage"). Reading such a file fails, so anything about to be opened is fetched first.
enum CloudFile {
    struct NotAvailable: LocalizedError {
        var name: String
        var errorDescription: String? {
            "“\(name)” is in iCloud and could not be downloaded. Check your connection and try again."
        }
    }

    static func isLocal(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        guard values?.isUbiquitousItem == true else { return true }
        return values?.ubiquitousItemDownloadingStatus == .current
    }

    /// Returns once the file's contents are on this Mac, asking iCloud for them if needed.
    static func ensureLocal(_ url: URL, timeout: Duration = .seconds(120)) async throws {
        guard FileManager.default.fileExists(atPath: url.path) || !isLocal(url) else { return }
        if isLocal(url) { return }
        try FileManager.default.startDownloadingUbiquitousItem(at: url)
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(400))
            // Resource values are cached per URL object; a fresh URL reads the current state.
            if isLocal(URL(fileURLWithPath: url.path)) { return }
        }
        throw NotAvailable(name: url.lastPathComponent)
    }
}
