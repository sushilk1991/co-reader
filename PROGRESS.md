# Coreader rebuild: progress

Branch `rebuild`. Clean rebuild of the old CoReader app (old code is in git history on `master`).

## Decisions (from Sushil, 2026-11-23)

- Clean native rebuild; shared core for Mac, later iOS/iPad.
- Mac app is a direct download (no sandbox) so it can run agent CLIs.
- Notes live in their own iCloud Drive folder as Markdown; Mastisk indexes them in place.
- Formats: EPUB, PDF, MOBI/AZW3 (+ saved web articles).
- Design: warm editorial (paper tones, serif titles, Stripe Press-like covers).
- Extra features approved: daily highlight review, paper tools, focus sessions, recap and
  summaries, cross-book connections, web articles, define and translate. Not asked for: read aloud.

## Architecture

- `CoreaderKit` (SwiftPM, Foundation only): models, library, notes Markdown, agents, papers,
  covers, review, graph. `coreader` CLI on top.
- Mac app (SwiftUI, xcodegen `project.yml`): foliate-js in a WKWebView for EPUB/MOBI/AZW3/articles
  (`Sources/CoreaderApp/Web/bridge.js`), PDFKit for PDF.
- Unattended UI checks: `scripts/dev_run.sh` launches off-screen, drives the app with one-line
  commands (`AppModel.debug`) and captures the window in-process (no Screen Recording permission
  on this Mac, so `screencapture` cannot be used).

## Done / verified

See the end-of-session report in the conversation and `git log`.

## Next

- iOS/iPad app on CoreaderKit (needs an iCloud container decision: iOS cannot open an arbitrary
  iCloud Drive folder without the user picking it).
- Read aloud, EPUB citation hover, Safari extension.
