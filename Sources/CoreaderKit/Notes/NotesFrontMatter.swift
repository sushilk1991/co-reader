import Foundation

/// The small subset of YAML that `notes.md` front matter uses. Coreader's own keys are
/// read into the document; every other key is kept as raw lines and written back
/// untouched, because Obsidian and friends store their own properties here.
enum NotesFrontMatter {
    static func parse(_ lines: [String], into document: inout NotesDocument) {
        var index = 0
        while index < lines.count {
            let line = lines[index]
            guard let (key, value) = topLevelKey(line) else {
                // Comments and anything unrecognised stay; blank lines are not worth keeping.
                if !NotesText.isBlank(line) { document.extraFrontMatter.append(line) }
                index += 1
                continue
            }
            var continuation: [String] = []
            var next = index + 1
            while next < lines.count, isContinuation(lines[next]) {
                continuation.append(lines[next])
                next += 1
            }
            switch key {
            case "title":
                document.title = scalar(value.isEmpty ? continuation.joined(separator: " ") : value)
            case "author", "authors":
                document.authors = list(value, continuation)
            case "coreader_id":
                document.bookID = scalar(value)
            case "source" where scalar(value) == "coreader":
                break
            case "updated":
                document.updated = ISODate.parse(scalar(value))
            default:
                document.extraFrontMatter.append(line)
                document.extraFrontMatter += continuation
            }
            index = next
        }
    }

    private static func topLevelKey(_ line: String) -> (key: String, value: String)? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let key = line[..<colon]
        guard !key.isEmpty, key.unicodeScalars.allSatisfy({
            ("a"..."z").contains($0) || ("A"..."Z").contains($0) || ("0"..."9").contains($0) || $0 == "_" || $0 == "-"
        }) else { return nil }
        let rest = line[line.index(after: colon)...]
        guard rest.isEmpty || rest.hasPrefix(" ") || rest.hasPrefix("\t") else { return nil }
        return (String(key), rest.trimmingCharacters(in: .whitespaces))
    }

    private static func isContinuation(_ line: String) -> Bool {
        guard !NotesText.isBlank(line) else { return false }
        return line.hasPrefix(" ") || line.hasPrefix("\t") || line.hasPrefix("- ") || line == "-"
    }

    static func scalar(_ text: String) -> String {
        let text = text.trimmingCharacters(in: .whitespaces)
        if text.count >= 2, text.hasPrefix("\""), text.hasSuffix("\"") {
            var out = ""
            var escaped = false
            for character in text.dropFirst().dropLast() {
                if escaped {
                    switch character {
                    case "n": out.append("\n")
                    case "t": out.append("\t")
                    default: out.append(character)
                    }
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else {
                    out.append(character)
                }
            }
            return out
        }
        if text.count >= 2, text.hasPrefix("'"), text.hasSuffix("'") {
            return text.dropFirst().dropLast().replacingOccurrences(of: "''", with: "'")
        }
        return text
    }

    private static func list(_ value: String, _ continuation: [String]) -> [String] {
        if value.hasPrefix("["), value.hasSuffix("]") {
            return splitFlow(String(value.dropFirst().dropLast())).map(scalar).filter { !$0.isEmpty }
        }
        if !value.isEmpty { return [scalar(value)] }
        return continuation.compactMap { line in
            let item = line.trimmingCharacters(in: .whitespaces)
            guard item.hasPrefix("-") else { return nil }
            return scalar(String(item.dropFirst())).nonEmpty
        }
    }

    /// Splits `a, "b, c", d` at the commas outside quotes.
    private static func splitFlow(_ text: String) -> [String] {
        var items: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false
        for character in text {
            if let open = quote {
                current.append(character)
                if escaped { escaped = false }
                else if character == "\\", open == "\"" { escaped = true }
                else if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
                current.append(character)
            } else if character == "," {
                items.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        items.append(current)
        return items
    }
}
