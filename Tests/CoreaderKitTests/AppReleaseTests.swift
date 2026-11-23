import Foundation
import Testing
@testable import CoreaderKit

@Test func versionsCompareNumberByNumber() throws {
    let v = { (s: String) in try #require(AppVersion(s)) }
    #expect(try v("1.0.2") < v("1.0.3"))
    #expect(try v("1.9") < v("1.10"))
    #expect(try v("v1.0") == v("1.0.0"))
    #expect(try !(v("2.0") < v("1.99.99")))
    #expect(try v(" v1.2.3 ").description == "1.2.3")
    for bad in ["", "latest", "1..2", "1.x", "-1.0", "1.0-beta"] { #expect(AppVersion(bad) == nil) }
}

@Test func releaseComesFromGitHubJSON() throws {
    let json = """
    {"tag_name":"v1.0.3","html_url":"https://github.com/o/r/releases/tag/v1.0.3","body":"  Fixes.\\n","draft":false,"prerelease":false,
     "assets":[{"name":"notes.txt","url":"https://api.github.com/repos/o/r/releases/assets/1","size":3},
               {"name":"Coreader-1.0.3.dmg","url":"https://api.github.com/repos/o/r/releases/assets/2","size":7654321}]}
    """
    let release = try #require(AppRelease.parse(gitHubJSON: Data(json.utf8)))
    #expect(release.version.description == "1.0.3")
    #expect(release.notes == "Fixes.")
    #expect(release.asset.absoluteString.hasSuffix("/assets/2"))
    #expect(release.assetName == "Coreader-1.0.3.dmg")
    #expect(release.size == 7_654_321)
}

@Test func releasesThatCannotBeInstalledAreIgnored() {
    func parse(_ json: String) -> AppRelease? { AppRelease.parse(gitHubJSON: Data(json.utf8)) }
    let asset = #"{"name":"a.dmg","url":"https://api.github.com/x","size":1}"#
    let page = #""html_url":"https://github.com/o/r""#
    #expect(parse(#"{"tag_name":"v2",\#(page),"assets":[\#(asset)]}"#) != nil)
    #expect(parse(#"{"tag_name":"v2",\#(page),"draft":true,"assets":[\#(asset)]}"#) == nil)
    #expect(parse(#"{"tag_name":"v2",\#(page),"prerelease":true,"assets":[\#(asset)]}"#) == nil)
    #expect(parse(#"{"tag_name":"nightly",\#(page),"assets":[\#(asset)]}"#) == nil)
    #expect(parse(#"{"tag_name":"v2",\#(page),"assets":[{"name":"a.zip","url":"https://api.github.com/x"}]}"#) == nil)
    #expect(parse(#"{"tag_name":"v2",\#(page),"assets":[{"name":"a.dmg","url":"http://insecure.example/x"}]}"#) == nil)
    #expect(parse(#"{"message":"Not Found"}"#) == nil)
    #expect(parse("not json") == nil)
}
