import Foundation

extension CoreaderCommand {
    /// Hand-rolled argument parsing: `--flag`, `--option value`, `--option=value`,
    /// and `--` to end options. Unknown options are errors, not positionals, so a typo
    /// never turns into a book title.
    struct Arguments {
        var command: String
        var positionals: [String] = []
        private var flags: Set<String> = []
        private var options: [String: [String]] = [:]

        init(_ arguments: [String], command: String, flags: Set<String> = [], options: Set<String> = []) throws {
            self.command = command
            var index = 0
            var optionsEnded = false
            while index < arguments.count {
                let argument = arguments[index]
                index += 1
                guard !optionsEnded, argument.hasPrefix("-"), argument.count > 1 else {
                    positionals.append(argument)
                    continue
                }
                if argument == "--" {
                    optionsEnded = true
                    continue
                }
                let parts = argument.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                let name = String(parts[0])
                if flags.contains(name), parts.count == 1 {
                    self.flags.insert(name)
                } else if options.contains(name) {
                    if parts.count == 2 {
                        self.options[name, default: []].append(String(parts[1]))
                    } else if index < arguments.count {
                        self.options[name, default: []].append(arguments[index])
                        index += 1
                    } else {
                        throw Failure.usage("\(name) needs a value.", command: command)
                    }
                } else {
                    throw Failure.usage("Unknown option '\(name)' for `coreader \(command)`.", command: command)
                }
            }
        }

        func has(_ flag: String) -> Bool { flags.contains(flag) }
        func value(_ option: String) -> String? { options[option]?.last }
        func values(_ option: String) -> [String] { options[option] ?? [] }

        func expectPositionals(_ range: ClosedRange<Int>, missing: String? = nil) throws {
            if positionals.count < range.lowerBound {
                throw Failure.usage(missing ?? "Missing argument.", command: command)
            }
            if positionals.count > range.upperBound {
                throw Failure.usage("Unexpected argument '\(positionals[range.upperBound])'.", command: command)
            }
        }
    }

    enum Help {
        static let overview = """
            coreader: query the Coreader library (books, highlights and notes).

            Usage: coreader <command> [options]

            Commands:
              books     List books (filter by status or rating)
              notes     Print one book's highlights and notes
              search    Search every highlight, note and tag
              export    All notes as one Markdown document
              text      Print the text of a book
              add       Import book files into the library
              open      Open a book in the Coreader app
              path      Print the library folder

            A <book> is an id, a folder slug, or part of a title.
            Most commands take --json. `coreader <command> --help` explains each one.

            Environment:
              COREADER_LIBRARY   use this library folder instead of the configured one
              COREADER_CACHES    use this folder for extracted book text

            """

        static let commands: [String: String] = [
            "path": """
                Usage: coreader path [--json]

                Prints the library folder. Books are in <path>/Books/<slug>/, each with
                book.json, notes.md and the book file. <path>/README.md describes the layout.

                """,
            "books": """
                Usage: coreader books [--status to-read|reading|read] [--min-rating N] [--json]

                Lists books, sorted by title, one per line with tab-separated columns:
                SLUG, STATUS, RATING (1-5 or -), PROGRESS, NOTES (count), TITLE, AUTHORS.

                  --status S        only books with this reading status
                  --min-rating N    only books rated N stars or more (unrated books are left out)
                  --json            an array of objects with id, slug, paths, link and the rest

                """,
            "notes": """
                Usage: coreader notes <book> [--json]

                Prints the book's notes.md: every highlight, note and saved image in reading
                order, each ending with a coreader:// link that opens the passage.

                  --json    {"book": {...}, "annotations": [{id, kind, quote, note, chapter,
                            tags, createdAt, position, locator, asset, link}]}

                """,
            "search": """
                Usage: coreader search <query> [--json]

                Finds highlights and notes whose quote, note or tags contain every word of the
                query. Case and accents are ignored. Each result shows the book, the position,
                the quote (as a blockquote), the reader's note and a coreader:// link.

                  --json    an array of {"book": {...}, "annotation": {...}}

                """,
            "export": """
                Usage: coreader export [--book <book>] [--since YYYY-MM-DD]

                Prints all notes as one Markdown document: a heading per book, the quoted
                passages as blockquotes, the reader's own notes as plain text, and a link per
                note. Read this before writing in the reader's voice.

                  --book B          only this book
                  --since DATE      only notes created on or after this date

                """,
            "text": """
                Usage: coreader text <book> [--list] [--section N] [--json]

                Prints the text of the book itself, section by section. Each section starts
                with a heading and a coreader:// link to that place. Books are long: use
                --list first, then --section.

                  --list         list the sections (number, length, title) instead of the text
                  --section N    only section N, as numbered by --list
                  --json         an array of {section, title, characters, file, link, text}

                PDF text is extracted on first use. For other formats the Coreader app saves
                the text when the book is opened; until then this command says so.

                """,
            "add": """
                Usage: coreader add <file>... [--title T] [--author A]... [--kind book|paper|article] [--json]

                Copies files (epub, pdf, mobi, azw3, html) into the library. Prints one line
                per file: "added" or "exists" (the same file is already in the library),
                then the slug and the title.

                  --title T     title to use (single file only; default is the file name)
                  --author A    author; repeat for several
                  --kind K      book (default), paper or article

                """,
            "open": """
                Usage: coreader open <book> [--page N]

                Opens the book in the Coreader app without bringing it to the front, and
                prints the coreader:// link it opened.

                  --page N    open a PDF at page N (counted from 1)

                """,
        ]

        static func text(for command: String) throws -> String {
            guard let text = commands[command] else { throw Failure.usage("Unknown command '\(command)'.") }
            return text
        }
    }
}
