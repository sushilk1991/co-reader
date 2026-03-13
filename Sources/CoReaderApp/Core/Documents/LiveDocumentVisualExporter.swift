import AppKit
import Foundation

struct LiveDocumentVisualExporter: DocumentVisualExporting {
    func exportPNG(_ visual: DocumentVisualAsset, for document: ReaderDocument) throws -> URL {
        let baseDirectory = try exportBaseDirectory()
        let documentDirectory = baseDirectory.appending(path: sanitized(document.title), directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: documentDirectory, withIntermediateDirectories: true)

        let exportURL = documentDirectory.appending(path: visual.suggestedFilename)
        let data = try pngData(for: visual)
        try data.write(to: exportURL, options: .atomic)
        return exportURL
    }

    private func exportBaseDirectory() throws -> URL {
        guard let applicationSupportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw NSError(
                domain: "CoReader.DocumentVisualExporter",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unable to resolve Application Support directory."]
            )
        }

        let directory = applicationSupportDirectory
            .appending(path: "CoReader", directoryHint: .isDirectory)
            .appending(path: "Exports", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func pngData(for visual: DocumentVisualAsset) throws -> Data {
        guard let image = NSImage(data: visual.imageData),
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(
                domain: "CoReader.DocumentVisualExporter",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Unable to encode exported PNG."]
            )
        }

        return pngData
    }

    private func sanitized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
