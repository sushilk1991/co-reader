import Foundation

struct EPUBReaderLoadState: Sendable {
    private var activeFileURL: URL?
    private var activeRequestID: UUID?

    mutating func startLoading(fileURL: URL) -> UUID {
        let requestID = UUID()
        activeFileURL = fileURL.standardizedFileURL
        activeRequestID = requestID
        return requestID
    }

    func accepts(requestID: UUID, fileURL: URL) -> Bool {
        activeRequestID == requestID && activeFileURL == fileURL.standardizedFileURL
    }
}
