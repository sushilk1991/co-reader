# Driving Coreader without a screen

The Debug build can be run off-screen and driven with one-line commands. Nothing appears
on the display and no window takes focus. Build first with `make build`.

```bash
export COREADER_DEV_STATE=$PWD/build/blind     # your own instance and scratch library
scripts/dev_start.sh                            # start (window 1320x860; SIZE=1100x720 to change)
scripts/dev_run.sh --shot /abs/path/shot.png    # capture the window, sheets and popovers
scripts/dev_run.sh --cmd "click 640 400"        # send a command
scripts/dev_run.sh --stop
```

Coordinates are points from the top-left corner of the window, the same as pixels in a
capture. Wait about a second after a command before capturing; opening a book takes a few.

## Input commands (what a person can do)

| Command | Effect |
| --- | --- |
| `click x y`, `dclick x y`, `rclick x y` | Click, double-click, right-click |
| `move x y` | Move the pointer (hover) |
| `scroll x y dy` | Scroll the view under that point by `dy` points, a little each frame |
| `drag x1 y1 x2 y2` | Press, drag, release |
| `type some text` | Type into the focused text field |
| `key return` | Also `escape`, `tab`, `left`, `right`, `up`, `down`, `delete`, `space` |

## Shortcuts for setting up a state

| Command | Effect |
| --- | --- |
| `import /abs/a.epub\|/abs/b.pdf` | Add files (the file dialog cannot be driven) |
| `link <url, arXiv id or DOI>` | Add a paper or save a web article |
| `open <part of a title>` / `close` | Open a book / go back to the shelf |
| `next`, `prev`, `goto 0.5` | Turn pages, jump to a fraction of the book |
| `select <text on the visible page>` | Select that text, as dragging over it would |
| `theme paper\|sepia\|dusk\|night` | Switch theme |
| `notebook`, `notebook close`, `notebook book=<title> kind=highlights\|notes\|images color=green sort=book\|newest\|oldest text=<words>` | Open the notebook (all notes), optionally filtered |
| `onboard done` / `onboard reset` | Skip or show the first-run screen |
| `dump` | Write a line of state to `$COREADER_DEV_STATE/debug.log` |

Sample files: `build/samples/alice.epub`, `build/samples/alice.azw3`, `build/samples/attention.pdf`.
The scratch library is `$COREADER_DEV_STATE/library` (plain folders and Markdown you can inspect).

Limits: the capture is drawn by the app itself, so text selection tint inside a PDF and
window shadows are not shown, and a small smudge can appear where a floating bar overlaps
book text. The system file dialog and native menus cannot be captured or driven: use the
shortcuts above and press `key escape` if one opens.

Scroll cost: `bench x y dy` scrolls down `dy` points and back in 40-point steps, finishing each step
before the next, and logs `bench steps=… total=… p95=… max=… over16=…` (milliseconds per step). Use this
to compare two builds; it is steady where wall-clock stutter counts are not.

Stutter: start with `COREADER_HITCHES=1` (`scripts/dev_start.sh COREADER_HITCHES=1`) and every stretch
where the main thread was blocked for more than 20 ms is written to `debug.log` as `hitch N ms`.
