import Foundation

protocol EPUBBookLoading: Sendable {
    func loadBook(from fileURL: URL) async throws -> EPUBBook
}
