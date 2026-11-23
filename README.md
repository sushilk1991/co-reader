# Coreader

A reading app for Mac: EPUB, PDF, MOBI/AZW3 and saved web articles on one shelf, with
highlights and notes kept as plain Markdown, and an AI side panel that uses the agent
apps already on your Mac (Claude Code, Codex, Antigravity). No API keys.

## What it does

- **Shelf**: To Read / Reading / Read, 1–5 star ratings, filters by kind and stars, search.
  Papers and plain PDFs get a designed cover (your agent's image generation), with a drawn
  cover until it arrives.
- **Reader**: paginated or scrolling, four themes, typeface and spacing controls, contents,
  search, focus mode. PDFs read in the same surface and tone as books.
- **Notes**: select to highlight in five colours, add notes, right-click a figure to keep
  it, or snip any area of the page. Everything lands in one `notes.md` per book, next to
  the book, with links that jump back to the exact place.
- **AI**: ask about a selection, the page, the whole book or your notes. Answers cite
  places in the book as buttons that take you there. Quick Explain, Look Up and Translate
  right beside the selection. Presets: summarize, recap so far, teach me this book, quiz me.
- **Papers**: add by arXiv id or DOI; real titles, authors and abstracts are looked up;
  click a citation to see the cited paper and add it to the library.
- **Memory**: a few highlights come back each day (spaced repetition); a graph shows the
  ideas and passages your books share; reading time and streak.
- **For your agents**: a `coreader` command and a skill let any agent search and use your
  notes ("write a post from my notes on X"). Any book can be distilled into a skill.
- **Connections**: optional Mastisk connector (indexes the same files, nothing copied) and
  a browser extension that sends pages to Coreader.

## Build and run

```bash
swift test                              # core library and CLI
xcodegen generate --spec project.yml
make build                              # the app (Debug)
make build-and-run-background
```

Requires macOS 15, Xcode, and `xcodegen`. See `AGENTS.md` for the layout and the on-disk
library format, `docs/driving-the-app.md` for running and checking the app without a
screen, and `integrations/` for the agent skill, Mastisk connector and browser extension.

## Where your library lives

`iCloud Drive/Coreader` by default (changeable in Settings). One folder per book:

```
Books/<book>/
  book.json     shelf, rating, progress
  notes.md      highlights, notes, saved images (the only copy)
  <book>.epub   the book
  cover.jpg
  assets/       snips and saved figures
```

Rendering of EPUB, MOBI and AZW3 uses [foliate-js](https://github.com/johnfactotum/foliate-js) (MIT).
