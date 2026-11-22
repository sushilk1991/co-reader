import Foundation
import Testing
@testable import CoreaderKit

@Test func deepLinkRoundTrips() {
    let a = DeepLink.annotation(bookID: "b1", annotationID: "abc")
    #expect(DeepLink(url: a.url) == a)
    let p = DeepLink.location(bookID: "b1", locator: Locator(page: 41))
    #expect(p.url.absoluteString.contains("page=42"))
    #expect(DeepLink(url: p.url) == p)
    #expect(DeepLink(url: URL(string: "https://example.com")!) == nil)
}
