import Foundation
import Testing
@testable import CoreaderKit

private let sampleBriefs: [(file: String, brief: CoverBrief)] = [
    ("attention-is-all-you-need", CoverBrief(
        title: "Attention Is All You Need", authors: ["Ashish Vaswani", "Noam Shazeer", "Niki Parmar"],
        summary: "A sequence model built only from attention.", kind: .paper)),
    ("fourier-transform", CoverBrief(
        title: "The Fourier Transform and Its Applications", authors: ["Ronald N. Bracewell"],
        summary: "Signals as sums of frequencies.", kind: .book)),
    ("deep-residual-learning", CoverBrief(
        title: "Deep Residual Learning for Image Recognition", authors: ["Kaiming He", "Xiangyu Zhang", "Shaoqing Ren", "Jian Sun"],
        summary: "Very deep convolutional networks trained with skip connections.", kind: .paper)),
    ("the-dream-machine", CoverBrief(
        title: "The Dream Machine", authors: ["M. Mitchell Waldrop"],
        summary: "J.C.R. Licklider and the revolution that made computing personal.", kind: .book)),
    ("navier-stokes", CoverBrief(
        title: "An Introduction to Fluid Dynamics", authors: ["G. K. Batchelor"],
        summary: "Viscous flow, vorticity and turbulence.", kind: .book)),
    ("long-title", CoverBrief(
        title: "On the Electrodynamics of Moving Bodies and Other Unreasonably Long Titles That Still Have to Fit",
        authors: ["Albert Einstein", "Mileva Marić"], summary: nil, kind: .article)),
    ("godel-escher-bach", CoverBrief(
        title: "Gödel, Escher, Bach", authors: ["Douglas R. Hofstadter"],
        summary: "Recursion, self-reference and the mind.", kind: .book)),
    ("seeing-like-a-state", CoverBrief(
        title: "Seeing Like a State", authors: ["James C. Scott"],
        summary: "How schemes to improve the human condition failed: grids imposed on forests, cities and farms.", kind: .book)),
]

@Test func proceduralCoverIsDeterministicSelfContainedSVG() {
    for (_, brief) in sampleBriefs {
        let svg = ProceduralCover.svg(for: brief, width: 800, height: 1200)
        #expect(svg == ProceduralCover.svg(for: brief, width: 800, height: 1200))
        #expect(svg.hasPrefix("<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 800 1200\""))
        #expect(svg.hasSuffix("</svg>\n"))
        #expect(svg.contains(CoverPalette.palette(for: brief).ground))
        // Nothing fetched from outside the file.
        #expect(!svg.contains("href"))
        #expect(!svg.contains("<image"))
        #expect(!svg.contains("nan") && !svg.contains("inf"))
    }
}

@Test func proceduralCoverParsesAsXML() throws {
    let tricky = CoverBrief(title: "Q&A: <Fish> & \"Chips\"", authors: ["A <B>"], summary: nil, kind: .book)
    for brief in sampleBriefs.map(\.brief) + [tricky] {
        let svg = ProceduralCover.svg(for: brief, width: 400, height: 600)
        let parser = XMLParser(data: Data(svg.utf8))
        #expect(parser.parse(), "invalid XML for \(brief.title): \(String(describing: parser.parserError))")
    }
    #expect(ProceduralCover.svg(for: tricky, width: 400, height: 600).contains("Q&amp;A: &lt;Fish&gt;"))
}

@Test func proceduralCoverCoversEveryMotifAcrossTitles() {
    var seen = Set<CoverMotif>()
    for index in 0..<80 { seen.insert(CoverMotif.motif(for: CoverBrief(title: "Volume \(index)"))) }
    #expect(seen == Set(CoverMotif.allCases))
    // Each family renders without blowing up at odd sizes.
    for index in 0..<24 {
        let svg = ProceduralCover.svg(for: CoverBrief(title: "Volume \(index)"), width: 90, height: 135)
        #expect(svg.contains("</svg>"))
    }
}

@Test func proceduralCoverWrapsLongTitlesInsideTheMargins() {
    let width = 800.0, inner = 800.0 - 2 * 72
    let long = ProceduralCover.layoutTitle(sampleBriefs[5].brief.displayTitle, width: inner, coverWidth: width)
    #expect(long.lines.count >= 4 && long.lines.count <= 8)
    #expect(long.lines.allSatisfy { ProceduralCover.estimatedWidth($0, size: long.size) <= inner })
    #expect(long.lines.joined(separator: " ") == sampleBriefs[5].brief.displayTitle)

    let short = ProceduralCover.layoutTitle("Dune", width: inner, coverWidth: width)
    #expect(short.lines == ["Dune"])
    #expect(short.size > long.size)

    // One unbreakable word is cut, not allowed to run off the cover.
    let giant = ProceduralCover.layoutTitle(String(repeating: "Pneumono", count: 12), width: inner, coverWidth: width)
    #expect(giant.lines.allSatisfy { ProceduralCover.estimatedWidth($0, size: giant.size) <= inner })
    #expect(giant.lines[0].hasSuffix("…"))

    // No orphaned short last word.
    let lines = ProceduralCover.wrap("The Structure of Scientific Revolutions Now", size: 60, width: 640)
    #expect(lines.last?.contains(" ") == true)
}

@Test func proceduralCoverOmitsTheAuthorLineWhenThereIsNone() {
    let with = ProceduralCover.svg(for: CoverBrief(title: "Solo", authors: ["Ada Lovelace"]), width: 400, height: 600)
    let without = ProceduralCover.svg(for: CoverBrief(title: "Solo"), width: 400, height: 600)
    #expect(with.contains("ADA LOVELACE"))
    #expect(without.components(separatedBy: "<text").count == 2)
}

/// `COREADER_COVER_SAMPLES=/dir swift test --filter writeProceduralCoverSamples` refreshes
/// the SVGs under docs/samples/procedural.
@Test(.enabled(if: ProcessInfo.processInfo.environment["COREADER_COVER_SAMPLES"] != nil))
func writeProceduralCoverSamples() throws {
    let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["COREADER_COVER_SAMPLES"] ?? "")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for (file, brief) in sampleBriefs {
        let svg = ProceduralCover.svg(for: brief, width: 800, height: 1200)
        try svg.write(to: directory.appendingPathComponent(file + ".svg"), atomically: true, encoding: .utf8)
    }
}
