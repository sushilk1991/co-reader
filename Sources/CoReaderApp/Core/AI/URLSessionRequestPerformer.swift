import Foundation

struct URLSessionRequestPerformer: HTTPRequestPerforming {
    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(for: request)
    }
}
