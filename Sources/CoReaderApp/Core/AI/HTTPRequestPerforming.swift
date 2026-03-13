import Foundation

protocol HTTPRequestPerforming: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, URLResponse)
}
