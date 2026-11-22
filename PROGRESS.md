# Coreader rebuild: progress

Branch `rebuild`. A clean rebuild of the old CoReader app (the old code is on `master`).

## Decisions (from Sushil, 2026-11-23)

- Clean native rebuild; shared core for Mac, later iOS/iPad.
- Mac app is a direct download (no sandbox) so it can run agent CLIs.
- Notes live in their own iCloud Drive folder as Markdown; Mastisk indexes them in place.
- Formats: EPUB, PDF, MOBI/AZW3 (+ saved web articles).
- Design: warm editorial (paper tones, serif titles, Stripe Press-like covers).
- Approved extras: daily highlight review, paper tools, focus sessions, recap and summaries,
  cross-book connections, web articles, define and translate. Not chosen: read aloud.

## Architecture

- `CoreaderKit` (SwiftPM): models, library, notes Markdown, agents, papers, covers, review,
  graph. `coreader` CLI on top. 258 unit tests.
- Mac app (SwiftUI, xcodegen `project.yml`): foliate-js in a WKWebView for
  EPUB/MOBI/AZW3/articles (`Sources/CoreaderApp/Web/bridge.js`), PDFKit for PDF.
- All writes of notes and metadata go through `WriteQueue` (ordered, drained on quit).
- Unattended checks: `scripts/dev_start.sh` + `docs/driving-the-app.md`. The app renders its
  own window for captures (this Mac has no Screen Recording permission and locks its screen).

## Verified in the running app (off-screen, 2026-11-23)

Import of EPUB, AZW3, PDF; arXiv import by id; article import by URL; paper detection and
metadata lookup; drawn and AI-designed covers; shelf tabs, filters, cells; EPUB and PDF
reading and paging (keys, edges); themes; highlight, note on highlight (typed, saved to
Markdown), notes panel; snip by dragging on EPUB and PDF; AI chat through Claude Code with
jump buttons; quick Explain; citation card in a PDF; notes graph node click; book-to-skill
end to end; settings and onboarding screens; `coreader` CLI inside the app bundle.

## Not verified (needs a person at a screen, or a live system)

- How the page-turn animation and PDF theme tint look (captures cannot show them).
- Popover placement, hover states, native menus and the file dialog.
- A library in real iCloud Drive (all runs used a scratch folder) and the iCloud download path.
- Mastisk connector applied to the live Mastisk (it needs `mastisk update`, which restarts it).
- Browser extension hand-off to the installed app; Codex and Antigravity in the chat panel
  (their sessions pass live tests in CoreaderKit; the panel was driven with Claude Code).
- Daily review with due cards (needs highlights at least a day old).

## Next

- iOS/iPad app on CoreaderKit (needs an iCloud container decision: iOS cannot open an
  arbitrary iCloud Drive folder without the user picking it).
- Notarized release build; import of the old CoReader notes (120 files, mostly saved AI
  chats, in the same iCloud folder under `Notes/`; left untouched).
- Read aloud, citation cards in EPUB, Safari extension, EPUB continuous scroll across chapters.
