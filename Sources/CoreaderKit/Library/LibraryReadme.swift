import Foundation

/// The `README.md` at the library root. It is written for agents (and curious people)
/// who land in the folder without knowing the app.
enum LibraryReadme {
    /// Bump when the text changes; `prepare()` rewrites older copies. A newer copy
    /// (written by a newer app on another device) is left alone, so two app versions
    /// sharing one iCloud folder do not fight over the file.
    static let version = 1

    static var marker: String { "<!-- coreader-readme v\(version) -->" }

    /// `existing` is nil when there is no README. A README without Coreader's marker is
    /// someone else's file (the folder may have had another life) and is never replaced.
    static func needsWrite(existing: String?) -> Bool {
        guard let existing else { return true }
        guard let first = existing.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first,
              first.hasPrefix("<!-- coreader-readme v"),
              let found = Int(first.dropFirst("<!-- coreader-readme v".count).prefix { $0.isNumber }) else { return false }
        return found < version
    }

    static var text: String {
        marker + "\n" + #"""
        # Coreader library

        This folder is the library of Coreader, a reading app for Mac. The app
        writes this file and replaces it on updates, so do not keep your own text here.

        Everything a person wrote while reading is plain Markdown in this folder. There is
        no database: these files are the only copy.

        ## Layout

        ```
        README.md                 this file
        Books/<slug>/
          book.json               metadata: title, authors, status, rating, progress
          notes.md                every highlight, note and saved image for the book
          <slug>.<ext>            the book itself (epub, pdf, mobi, azw3, html)
          cover.jpg|png           cover image
          assets/                 images saved or snipped from the book
          chats/                  saved AI conversations, Markdown
        review.json               spaced-repetition state for the daily review
        ```

        `<slug>` is a lowercase, hyphenated form of the title, for example
        `thinking-fast-and-slow`. A book's permanent identity is the `id` in `book.json`,
        not the folder name.

        ## Rules for agents

        - Read anything. `notes.md` is the reader's own voice: quote it exactly.
        - Do not edit `book.json` by hand. The app owns it, and a half-written file hides
          the book from the shelf. Change status, rating and metadata in the app.
        - Do not rename or move book folders or the files inside them.
        - You may edit `notes.md` (see the format below). Write the whole file to a
          temporary file and rename it over the original, because iCloud and the app read
          it at any moment.
        - Extracted book text and search indexes live in `~/Library/Caches/Coreader/`.
          They are derived and may be missing; `coreader text <book>` gets the text.

        ## The `coreader` command

        ```
        coreader books [--status to-read|reading|read] [--min-rating N] [--json]
        coreader notes <book> [--json]        one book's notes (Markdown by default)
        coreader search <query> [--json]      search every quote, note and tag
        coreader export [--book X] [--since YYYY-MM-DD]   all notes as one document
        coreader text <book> [--list] [--section N]       the book's own text
        coreader open <book> [--page N]       open the book in the app
        coreader add <file>...                import files
        coreader path                         print this folder
        ```

        `<book>` is an id, a folder slug, or part of a title.

        ## notes.md

        ```markdown
        ---
        title: "Thinking, Fast and Slow"
        author:
          - "Daniel Kahneman"
        coreader_id: 0b54c1de-6f0a-4a43-9a51-0a3c8a3a8f0e
        source: coreader
        updated: 2026-11-23T10:15:30Z
        ---

        # Thinking, Fast and Slow

        ## The Characters of the Story

        <!-- coreader {"id":"a1b2c3d4e5f6","kind":"highlight","color":"yellow","locator":{"fraction":0.08,"label":"p. 21","page":20},"chapter":"The Characters of the Story","createdAt":"2026-11-20T08:00:00Z","tags":["attention"]} -->
        > System 1 operates automatically and quickly, with little or no effort.

        The reader's own note about the passage. Any Markdown, any number of paragraphs.

        [p. 21](coreader://open?book=0b54c1de-6f0a-4a43-9a51-0a3c8a3a8f0e&a=a1b2c3d4e5f6)
        ```

        Each highlight, note or saved image is one block:

        1. A single `<!-- coreader {...} -->` line starts the block. It holds what the app
           needs and people do not: id, kind (`highlight`, `note`, `image`), color, position
           in the book, chapter, creation time, tags, image file. Leave it as it is.
        2. The quoted passage as a `>` blockquote, directly under that line.
        3. For images, `![caption](assets/<file>)`.
        4. The reader's note: ordinary Markdown paragraphs.
        5. A link line `[p. 21](coreader://open?book=...&a=...)` ends the block. Opening the
           link shows the passage in the app.

        Blocks are in reading order under `## <chapter>` headings.

        What you may change:

        - Edit the quote and the note text freely. The app reads them from the Markdown, so
          edits survive.
        - Write your own text above the first block, between blocks (after a link line) or
          after the last block, for example a `## Summary` section at the end. The app
          keeps it.
        - Rename a `## <chapter>` heading directly above a block to rename that chapter.
        - Delete a whole block (from its comment line to its link line) to delete the note.
        - Add a note by appending a block with a new id of 12 lowercase hex characters;
          only `"id"` is required in the comment.

        ## Deep links

        ```
        coreader://open?book=<id>                  the book where the reader left off
        coreader://open?book=<id>&a=<annotation>   a highlight or note
        coreader://open?book=<id>&page=<n>         a PDF page, counted from 1
        coreader://open?book=<id>&cfi=<epubcfi>    a place in an EPUB
        ```

        When you quote the reader's notes to them, keep the link next to the quote so they
        can jump back to the page.
        """# + "\n"
    }
}
