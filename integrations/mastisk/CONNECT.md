# "Connect to Mastisk" in Coreader's onboarding

What the app has to do, written for whoever implements it in Swift. Every fact
about Mastisk here was checked in its source at `a784800` or against the
running daemon. Facts about the connector describe [`mastisk.patch`](mastisk.patch),
which the Mastisk owner has to install first ([README](README.md#installing-the-patch)).

The app never writes into Mastisk's files and never edits its `config.toml`.
It runs one Mastisk command and reads two local URLs.

## 1. Detect Mastisk

Run these in order and stop at the first that settles it. None of them
changes anything.

| Check | How | Meaning |
| --- | --- | --- |
| CLI installed | First executable of: `mastisk` on `PATH`, then `~/.local/bin/mastisk`. A Mac app launched from Finder does not have `~/.local/bin` on its `PATH`, so check the absolute path too. | Not found: Mastisk is not on this Mac. Hide the step or show "Mastisk not found". |
| Remote daemon | Environment variable `MASTISK_URL` is set. | Mastisk runs on another machine. The connector must be switched on there; show that and stop. |
| Daemon running | `GET http://127.0.0.1:5555/api/health` with a 2 second timeout. A running Mastisk answers `200` with `{"ok": true, "public_url": …}`. | No answer: Mastisk is installed but not running. Connecting still works (step 2 does not need the daemon); verification waits. |
| Connector installed | `GET http://127.0.0.1:5555/api/coreader`. `200` with JSON: installed. `404`: this Mastisk does not have the connector. If the daemon is down, run `mastisk coreader status --json` instead: exit code `2` ("No such command 'coreader'") means not installed. | Not installed: show "Your Mastisk needs the Coreader connector" with a pointer to `integrations/mastisk/README.md`. Do not offer Connect. |

Notes:

- The port is `5555` unless the user changed it (`port` in
  `~/Library/Application Support/Mastisk/config.toml`, or `MASTISK_PORT`).
  Reading the port from that file is optional; if you do, treat the file as
  read-only. It is mode `0600` and holds API keys, so never log or copy it.
- Call the API on `127.0.0.1` or `localhost` only. Mastisk can treat a
  request under another host name as tunnel traffic, and then answers `404`
  to everything except its capture endpoint.
- `public_url` in the health answer is the address for links the user opens
  on another device. Coreader does not need it.

## 2. Connect

Before connecting, make sure Coreader has written its own
`~/Library/Application Support/Coreader/config.json` with `libraryRoot`.
Then run, with a timeout (30 seconds is plenty) like every other child
process in the app:

```
mastisk coreader connect --json
```

With no `--library`, Mastisk follows `libraryRoot` from Coreader's
`config.json`, so the two apps cannot disagree about the folder, and moving
the library later needs nothing from Mastisk. To pin a folder instead, pass
`--library <absolute path>`; the folder must exist, or the command exits `1`.

The command writes `[coreader] enabled = true` and `library_root` into
Mastisk's `config.toml`, indexes the library straight away, and prints one
JSON object on stdout:

```json
{
  "enabled": true,
  "library_root": "/Users/me/Library/Mobile Documents/com~apple~CloudDocs/Coreader",
  "root_source": "coreader-config",
  "library_exists": true,
  "books": 12,
  "last_scan": {"enabled": true, "upserted": 12, "unchanged": 0, "unreadable": 0, "removed": 0, "skipped": null, "scanned_at": "2026-11-22T19:06:11+00:00", "library_root": "…"}
}
```

- `root_source` is `config.toml` (pinned with `--library`), `coreader-config`
  (from Coreader's `config.json`) or `default`.
- `library_exists` is whether `<library_root>/Books` is a folder. `false` on
  a brand-new library is fine.
- `last_scan.skipped` is a sentence when the library could not be listed;
  show it.

Exit codes: `0` connected; `1` bad folder, or `MASTISK_URL` is set; `2` the
`coreader` command does not exist (connector not installed).

No Mastisk restart is needed. The running daemon rereads the setting on its
next scan, at most five minutes later.

## 3. Verify (read-only)

If the daemon is running:

1. `GET http://127.0.0.1:5555/api/coreader` and check `enabled == true` and
   that `library_root` is Coreader's library root (compare resolved paths).
   `books` is the number of books that have a `notes.md`.
2. Optional, for a visible confirmation: `GET /api/coreader/books` returns
   `[{id, slug, path, title, author, highlight_count, updated_at, deep_link}]`.
   `id` is the `coreader_id` from the notes front matter and `deep_link` is
   `coreader://open?book=<id>`.

If the daemon is not running, the JSON from step 2 is the verification.

Show the result as "Connected. Mastisk sees N books." and, when `books` is
`0` and the library has notes, show `last_scan.skipped`.

## 4. After onboarding

- **Settings.** Show the state from `GET /api/coreader` (or
  `mastisk coreader status --json`) and a switch. Off is
  `mastisk coreader disconnect --json`; it removes the notes from Mastisk's
  search and touches no file.
- **Fresh notes sooner (optional).** Mastisk rescans every five minutes. To
  make a new highlight searchable at once, `POST
  http://127.0.0.1:5555/api/coreader/scan` (no body) after writing
  `notes.md`. Debounce it; a scan only re-reads files whose size or
  modification time changed. Ignore failures: the next scheduled scan
  catches up.
- **Do not store the connection state in Coreader.** Mastisk's answer is the
  truth; ask it when the settings pane opens.

## What Mastisk reads from the library

So the notes writer knows what matters to the connector:

- Only `<libraryRoot>/Books/<slug>/notes.md`. Folders whose name starts with
  `.` are skipped. A book without `notes.md` is not listed.
- Front matter keys `coreader_id`, `title` and `author`. If `coreader_id` or
  `title` is missing it falls back to `id`, `title` and `author` in
  `book.json`, then to the folder name. Bad YAML is tolerated.
- The rest of the file is treated as plain Markdown. Blockquote runs are
  counted as highlights; nothing else about the layout is assumed.
- Two folders with the same id: the first by folder name wins, the other is
  ignored with a warning in Mastisk's log.
- Atomic replace (write a temporary file, then rename) is what the connector
  expects. Temporary files should not be named `notes.md`.

## Mastisk on another machine (what the app does today)

Implemented in `MastiskLocator` (CoreaderKit) and `Integrations.mastiskState`.

1. `GET http://127.0.0.1:5555/api/health`. If Mastisk is on this Mac the steps above apply,
   and first-run onboarding switches the connector on without asking.
2. Otherwise the address that answered last time, then every online computer in
   `tailscale status --json`: `GET https://<name>:8443/api/health` and
   `https://<name>/api/health`, in parallel, 3 second timeout. A host counts as Mastisk
   only if the answer is `{"ok": true, "public_url": …}`.
3. `GET <base>/api/coreader` on the one that answered. Only these two read-only requests
   are sent; no book, note or path leaves the Mac.
4. "Connected" is shown when the connector there is on and its `library_root` is the same
   folder inside iCloud Drive as this library (compared below `com~apple~CloudDocs`,
   ignoring case). iCloud carries the notes to that machine; Mastisk reads them there.

The connector cannot be switched on from another machine: that takes
`mastisk coreader connect` on the host, and the app says so.
