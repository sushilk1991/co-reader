import Foundation
import Testing
@testable import CoreaderKit

@Suite struct MastiskLocatorTests {
    static let health = Data(#"{"ok": true, "public_url": "https://mini.example.ts.net:8443"}"#.utf8)
    static let status = Data("""
    {"Self": {"DNSName": "book.example.ts.net.", "Online": true, "OS": "macOS"},
     "Peer": {
       "a": {"DNSName": "mini.example.ts.net.", "Online": true, "OS": "macOS"},
       "b": {"DNSName": "phone.example.ts.net.", "Online": true, "OS": "iOS"},
       "c": {"DNSName": "old.example.ts.net.", "Online": false, "OS": "linux"},
       "d": {"DNSName": "bad host/../x.", "Online": true, "OS": "linux"}}}
    """.utf8)

    static func server(_ answers: [String: (Int, Data)]) -> MastiskLocator {
        MastiskLocator { url in answers[url.absoluteString].map { (status: $0.0, body: $0.1) } }
    }

    @Test func candidatesAreOnlineComputersOnly() {
        let urls = MastiskLocator.candidates(fromTailscaleStatus: Self.status).map(\.absoluteString)
        #expect(urls == ["https://mini.example.ts.net", "https://mini.example.ts.net:8443"])
        #expect(MastiskLocator.candidates(fromTailscaleStatus: nil).isEmpty)
        #expect(MastiskLocator.candidates(fromTailscaleStatus: Data("nonsense".utf8)).isEmpty)
    }

    @Test func localMastiskWinsOverTailnet() async {
        let locator = Self.server([
            "http://127.0.0.1:5555/api/health": (200, Self.health),
            "http://127.0.0.1:5555/api/coreader": (200, Data(#"{"enabled": false, "library_root": "/x", "books": 0}"#.utf8)),
            "https://mini.example.ts.net:8443/api/health": (200, Self.health),
        ])
        let found = await locator.locate(remembered: nil, tailscaleStatus: Self.status)
        #expect(found?.isLocal == true)
        #expect(found?.connector == .init(enabled: false, libraryRoot: "/x", books: 0))
    }

    @Test func findsMastiskOnTheTailnet() async {
        let locator = Self.server([
            "https://mini.example.ts.net:8443/api/health": (200, Self.health),
            "https://mini.example.ts.net:8443/api/coreader": (200, Data(#"{"enabled": true, "library_root": "/Users/a/Library/Mobile Documents/com~apple~CloudDocs/Coreader", "books": 3}"#.utf8)),
        ])
        let found = await locator.locate(remembered: nil, tailscaleStatus: Self.status)
        #expect(found?.baseURL.absoluteString == "https://mini.example.ts.net:8443")
        #expect(found?.isLocal == false)
        #expect(found?.connector?.books == 3)
    }

    @Test func otherServicesAndOldMastiskAreToldApart() async {
        // Something else answering /api/health is not Mastisk.
        let other = Self.server(["https://mini.example.ts.net:8443/api/health": (200, Data(#"{"status": "ok"}"#.utf8))])
        #expect(await other.locate(remembered: nil, tailscaleStatus: Self.status) == nil)
        // A Mastisk without the connector answers 404 on /api/coreader.
        let old = Self.server([
            "https://mini.example.ts.net:8443/api/health": (200, Self.health),
            "https://mini.example.ts.net:8443/api/coreader": (404, Data()),
        ])
        let found = await old.locate(remembered: nil, tailscaleStatus: Self.status)
        #expect(found != nil && found?.connector == nil)
    }

    @Test func theMastiskWithTheConnectorOnIsPreferred() async {
        let status = Data(#"{"Peer": {"a": {"DNSName": "aaa.ts.net.", "Online": true, "OS": "linux"}, "b": {"DNSName": "bbb.ts.net.", "Online": true, "OS": "macOS"}}}"#.utf8)
        let locator = Self.server([
            "https://aaa.ts.net:8443/api/health": (200, Self.health),
            "https://bbb.ts.net:8443/api/health": (200, Self.health),
            "https://bbb.ts.net:8443/api/coreader": (200, Data(#"{"enabled": true, "library_root": "/x", "books": 1}"#.utf8)),
        ])
        #expect(await locator.locate(remembered: nil, tailscaleStatus: status)?.baseURL.host == "bbb.ts.net")
    }

    @Test func rememberedAddressIsTriedWithoutTailscale() async {
        let locator = Self.server(["https://kept.example:8443/api/health": (200, Self.health)])
        let found = await locator.locate(remembered: URL(string: "https://kept.example:8443"), tailscaleStatus: nil)
        #expect(found?.baseURL.host == "kept.example")
    }

    @Test func sharedLibraryMeansSameICloudFolder() {
        let mine = "/Users/me/Library/Mobile Documents/com~apple~CloudDocs/CoReader"
        #expect(MastiskLocator.sharesLibrary(local: mine, remote: "/Users/other/Library/Mobile Documents/com~apple~CloudDocs/Coreader/"))
        #expect(!MastiskLocator.sharesLibrary(local: mine, remote: "/Users/other/Library/Mobile Documents/com~apple~CloudDocs/Reading"))
        #expect(!MastiskLocator.sharesLibrary(local: "/Users/me/Documents/Coreader", remote: "/Users/me/Documents/Coreader"))
    }
}

@Test func sameFolderIgnoresCaseAndTrailingSlash() {
    #expect(MastiskLocator.sameFolder("/tmp/CoReader/", "/tmp/coreader"))
    #expect(!MastiskLocator.sameFolder("/tmp/coreader", "/tmp/reading"))
}
