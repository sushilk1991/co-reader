# Coreader connector for Mastisk

Makes Coreader's reading notes show up in Mastisk's search and Ask, with one
copy of every Markdown file. Coreader works the same with or without it.

Mastisk has no plugin mechanism, so the connector is a small patch to Mastisk
itself: [`mastisk.patch`](mastisk.patch) (two commits on top of Mastisk
`a784800`; both are in Mastisk `main` since `93655da`). Nothing in this folder touches a running Mastisk until that patch
is installed by its owner.

## What it does

- Every five minutes Mastisk looks at `<Coreader library>/Books/*/notes.md` and
  keeps one row per book in a new `coreader_books` table: id, title, author,
  the file's path **relative to the library**, a highlight count, and a search
  index of the note text.
- `GET /api/search` (the command palette) and `POST /api/ask` (and so
  `mastisk ask`, which Mastisk's agents and the user's coding agents use)
  return these as results of kind `coreader`. Ask reads the notes file itself
  at question time and gives the model the `coreader://open?book=<id>` link, so
  an answer can point back into the book.
- It never writes to the Coreader library and never creates a file in the
  Mastisk vault.

## How "no duplication" works

Both apps read the same file. Coreader writes `Books/<slug>/notes.md` in its
library (by default `iCloud Drive/Coreader`); Mastisk indexes that file where
it is. iCloud Drive syncs the one file to every device signed in to the same
Apple ID, and that is the only sync involved.

What Mastisk stores is an index, not a second set of notes: the `search_text`
column is rebuilt from the file whenever its size or modification time
changes, is dropped when the book or the connector goes away, and can be
deleted without losing anything. It is the same kind of thing as Coreader's
own `~/Library/Caches/Coreader/`.

Checked in the test suite and in an end-to-end run: after a scan the vault
has no new files and every library file has the same size and modification
time as before.

## Why this design

Verified against Mastisk `a784800` (`~/Code/mastisk`):

| Option | Verdict | Evidence |
| --- | --- | --- |
| (d) A plugin module | Not possible | No plugin, entry-point or connector mechanism exists. Every mirror is imported by name in `src/mastisk/scheduler.py:136-164`. |
| Existing "local repos" | Wrong tool | `mastisk add-local-repo` requires a `.git` directory (`src/mastisk/cli.py:1316`) and feeds the GitHub idea generator, not search. |
| Existing Library (`library/books/<slug>.md`) | Would duplicate | The scanner globs only flat `library/books/*.md` (`src/mastisk/library/sync.py:799-803`), reads highlights only from a `## Highlights` bullet list, and then writes a quote file per highlight into the vault (`recover_highlight_quotes`, `sync.py:530`). Feeding it Coreader notes means converting and copying them. |
| `mastisk ingest <file>` | Would duplicate | Ingest turns a file into a Source and a compiled article: a second, diverging copy. |
| (b) Symlink from the vault | Does not work | Ask refuses any file whose resolved path leaves the vault (`src/mastisk/routes/ask.py:742-752`), the Library scanner calls `path.relative_to(vault_dir())` (`sync.py:255`), and iCloud Drive does not sync what a symlink points to. |
| (c) Coreader library inside the vault | Still needs a patch, and worse | Nothing indexes arbitrary Markdown in the vault; each folder has its own scanner (`scheduler.py:148-164`), and the editor accepts only `journal/`, `_notes/`, `projects/`, `content/` (`src/mastisk/vault_paths.py:8`). It would also put EPUB and PDF files in the vault and tie Coreader's folder to Mastisk's. |
| **(a) Index the Coreader folder in place** | **Chosen** | It is how Mastisk already treats its "Personal OS" files: a table row with a path, and the body read from the file when Ask needs it (`_FILE_MIRRORS` at `ask.py:41`, `_search_personal_files` at `ask.py:687-700`, `_search_personal_os_mirrors` at `src/mastisk/db/queries.py:1326`). The patch adds one more mirror whose root is outside the vault. |

Two details follow from how Mastisk runs:

- **No restart to connect.** `get_settings()` is cached for the life of the
  daemon (`src/mastisk/settings.py:518`). The connector reads its
  `[coreader]` table from `config.toml` on every scan instead, the way
  `read_capture_bearer_token` already does (`settings.py:505`), so the CLI
  can switch it on while the daemon keeps running.
- **Safe for an unpatched Mastisk.** The top-level settings ignore unknown
  keys (`extra="ignore"`, `settings.py:424`), so a `[coreader]` table in
  `config.toml` does not stop an older Mastisk from starting. Checked by
  loading unpatched settings with that table present.

## Files here

| Path | What |
| --- | --- |
| `mastisk.patch` | The whole change as a `git am` patch: new files, wiring, tests, docs. |
| `src/mastisk/coreader/` | Copy of the new package: `config.py` (where the library is, on or off) and `sync.py` (scan, read, status). |
| `src/mastisk/routes/coreader.py` | Copy of the new API routes. |
| `tests/test_coreader.py` | Copy of the tests. |
| `fixtures/Coreader/` | A two-book library for trying it out. |
| `CONNECT.md` | What the Coreader app does in its "Connect to Mastisk" step. |

The copies are for reading; the patch is what gets applied. It also edits
existing Mastisk files: `settings.py` (the `[coreader]` table),
`db/schema.sql` (the table), `scheduler.py` (the scan), `db/queries.py`
(search), `routes/ask.py` (Ask), `app.py` (routes), `cli.py` (commands),
two frontend files (the palette opens the deep link), `README.md` and
`docs/agents/api.md`.

## Installing the patch

Do this once, where Mastisk's source is kept. The patch applies cleanly to
`a784800`.

```bash
cd ~/Code/mastisk
git am /path/to/co-reader/integrations/mastisk/mastisk.patch
pytest tests/test_coreader.py     # in the repo's dev environment
mastisk update
```

`mastisk update` rebuilds the frontend, reinstalls the package and **restarts
the daemon** (it drains running agent work first). That restart is the only
one this integration ever needs, and it is the owner's call when to do it.
Until then the running Mastisk is unchanged.

`mastisk update` pulls with `--ff-only`, so a patch that exists only as a
local commit will block later pulls. Push the commit to the Mastisk
repository (or land it there first and let `mastisk update` pull it).

## Turning it on

```bash
mastisk coreader connect                        # follow the Coreader app's own folder
mastisk coreader connect --library ~/Reading    # or name the library folder
mastisk coreader status                         # on/off, folder, books indexed
mastisk coreader scan                           # rescan now
mastisk coreader disconnect                     # off; notes leave search and Ask
```

All four take `--json`. No restart is needed for any of them: `connect`
indexes the library at once, and the daemon picks the change up on its next
five-minute scan.

`connect` writes this to `~/Library/Application Support/Mastisk/config.toml`:

```toml
[coreader]
enabled = true
library_root = ""    # or an absolute path
```

With `library_root` empty, Mastisk uses the folder Coreader records in
`~/Library/Application Support/Coreader/config.json` (`libraryRoot`), then
`iCloud Drive/Coreader`, then `~/Documents/Coreader`. So moving the library
inside Coreader needs no change in Mastisk.

To try it without Coreader:

```bash
mastisk coreader connect --library /path/to/co-reader/integrations/mastisk/fixtures/Coreader
curl -s 'http://127.0.0.1:5555/api/search?q_param=snooze'
mastisk coreader disconnect
```

## Limits

- **New notes appear within five minutes**, not at once (the scan interval),
  unless something calls `POST /api/coreader/scan` or `mastisk coreader scan`.
- **Keyword search, not embeddings.** Mastisk's Ask retrieves with SQLite
  full-text and substring matching; it uses embeddings only for filtering RSS
  items. Reading notes are matched by words in the title, author or note text.
- **Mastisk's Library page does not list Coreader books.** They are a
  separate kind. The palette result opens the book in Coreader through the
  deep link, which works only on a Mac with Coreader installed. In Ask's
  source list the entry is shown without a link, because the PWA only links
  `http(s)` and in-app paths.
- **Agents do not write articles from reading notes.** The Compiler and
  Synthesizer are not fed these files; that would create derived copies and
  is left out on purpose.
- **Files iCloud has evicted.** A daemon that reads an evicted iCloud file gets an
  error at once instead of the download. The scan therefore asks iCloud for the file
  (`brctl download`) and retries for a few seconds; if it still is not there, the last
  index is kept and the next scan tries again. Checked on a real evicted `notes.md`.
- **The Mac that runs Mastisk must see the library.** With the default
  iCloud Drive location that means the same Apple ID on that Mac. Coreader on
  another Mac finds that Mastisk over Tailscale (see [CONNECT.md](CONNECT.md))
  and reports it as connected when both use the same iCloud Drive folder. The
  `mastisk coreader` commands themselves run only on the host.
- **Images** in notes (`assets/…`) are not indexed; the Markdown reference is
  passed through as text.
- `last_scan` in the status is kept in memory, so it is `null` after a
  restart until the first scan.

## What was tested

- `tests/test_coreader.py`: 12 tests, passing in a scratch clone with a
  temporary data directory, vault and fixture library.
- The full Mastisk suite in the same clone: 1379 tests. Two failed only
  because the isolated run set `MASTISK_PORT=59555` and they assert port
  5555; both pass with the default port.
- `ruff check` on the new files, and the frontend `tsc -b` typecheck.
- End to end: the patched daemon on `127.0.0.1:59555` with a throwaway home
  and vault. `connect` from the CLI, the API and search answered, a new
  highlight was found by the scheduled scan, `disconnect` removed the
  results, and the vault stayed empty.

Not tested: the patch on the live Mastisk and its real database, a library
in real iCloud Drive (eviction is simulated with an unreadable file), the
rebuilt PWA in a browser, and `mastisk update` with the patch applied.

## Sign in with Apple in Mastisk: not needed

The idea was that both apps would "use the same account". They already do, in
the only sense that matters here: iCloud Drive belongs to the Apple ID signed
in to macOS, not to an app. Any process running as the user can read
`~/Library/Mobile Documents/com~apple~CloudDocs/`, which is how Mastisk
already keeps its vault there without any sign-in.

Sign in with Apple is a different thing. It proves a person's identity to a
web service and gives no access to their iCloud Drive files. Mastisk is a
local daemon with no accounts, so adding it would mean an Apple Developer
service ID, a redirect URL, and a login screen, and afterwards the files
would sync exactly as they do now.

It would only be worth revisiting if Mastisk became a hosted service with
several users, or if Coreader on iPhone had to reach a Mastisk that is not on
the same Apple ID. Neither is planned.
