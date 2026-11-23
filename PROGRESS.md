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

## 2026-11-23: decisions from Sushil, acted on

- `rebuild` merged into `master` and pushed (258 tests pass on the merge).
- Mastisk connector installed: patch pushed as Mastisk `7f1bb45`, `mastisk update` run, `mastisk coreader connect` done. It reports 0 books until the real library has a `Books` folder.
- Old iCloud `CoReader` notes: not imported. All 120 are AI-chat stubs from test runs of the old app (four distinct bodies such as "Summary created.", sources under `/tmp`). Left in place.
- iOS: the app will ask once for the Coreader folder in iCloud Drive (folder picker), keeping plain files.
- Release: `scripts/release.sh` and `docs/releasing.md`. Developer ID certificate created (Sushil signed in to the developer portal); `dist/Coreader-1.0.0.dmg` is signed, notarized and stapled.

## 2026-11-23: pre-release audit and 1.0.0 release

- Mastisk is found automatically: this Mac first, then tailnet computers (`MastiskLocator`, `integrations/mastisk/CONNECT.md`). First-run onboarding connects a local Mastisk without asking (Sushil's request).
- Mastisk connector fetches iCloud-evicted notes before indexing (Mastisk `93655da`); checked on a real evicted `notes.md` on the Mac mini.
- Codex audit, 12 findings. Fixed: foreign README overwritten, evicted `notes.md`/`book.json` handling, external edit lost between read and write, unusable library folder remembered, Tailscale CLI mode, best-candidate choice and no redirects in discovery, stale results after leaving the screen, command installer, Intel build (now universal).
- Left as they are, by decision: auto-connect of a local Mastisk and AI covers on by default (both asked for by Sushil); the off-screen debug hooks stay in Release builds (they need environment variables set by whoever launches the app).
- Not verified: discovery through `tailscale status` on a second Mac (the Mac mini is its own Mastisk host, so only the remembered-address path ran against the real server), the Intel slice, opening the DMG on another Mac.

## 2026-11-23: 1.0.1 to 1.0.3

- 1.0.1: app icon (there was no asset catalog). `scripts/make_app_icon.py` redraws it.
- 1.0.2: drawn covers vary (keywords weight the motif instead of deciding it; `Book.coverVariant`
  gives "Design a New Cover" a new design each time), dark PDF tint fixed (filters run in linear
  light), appearance popover no longer clipped.
- 1.0.3: shelf scrolling (see the commit message for numbers; `bench` debug command measures it),
  at most two AI cover jobs at once, in-app updates (`Updater.swift`, `docs/releasing.md`).
- Not verified on a real screen: the dark PDF tint, hover-driven controls on the shelf (star
  buttons and the menu button appear under the pointer), the updater's sheet on a visible window.
- Updates need a signed-in `gh` while the repository is private.
