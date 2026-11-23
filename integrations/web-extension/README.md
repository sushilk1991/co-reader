# Save to Coreader (browser extension)

Sends the page you are reading, or the text you selected, to the Coreader app
on the same Mac. Works in Chrome, Arc, Brave and Edge (Manifest V3).

The extension does not read or upload page content. It hands Coreader a link
containing the page address, its title and, if you asked for it, the selected
text. Coreader fetches and cleans the article itself.

## Install (unpacked)

1. Open `chrome://extensions` (`arc://extensions`, `brave://extensions`,
   `edge://extensions`).
2. Turn on **Developer mode**.
3. Choose **Load unpacked** and pick this folder (`integrations/web-extension`).
4. Pin "Save to Coreader" to the toolbar.

The first save makes the browser ask "Open Coreader?". Tick "Always allow" to
skip the question next time. If nothing happens, Coreader is not installed or
has not registered the `coreader` URL scheme yet.

## Use

| How | What it does |
| --- | --- |
| Toolbar button | Opens a small panel with **Save page** and **Save selection**. Enter saves the page. |
| Right-click the page | **Save page to Coreader** |
| Right-click selected text | **Save selection to Coreader** |
| `Option+Shift+S` | Saves the page without opening the panel. |

The toolbar icon shows a tick for a moment after a right-click or shortcut
save, and `!` when the page cannot be saved. Change the shortcut, or give
"Save selection" one, at `chrome://extensions/shortcuts`.

Only `http` and `https` pages can be saved. Browser pages, local files and
the extension store are refused. Where the browser will not let an extension
read the page (its PDF viewer, for example), the right-click item falls back
to the browser's own copy of the selection, which has no line breaks.

## The URL contract

```
coreader://save?url=<url>&title=<title>&selection=<selection>&truncated=1
```

| Parameter | Required | Value |
| --- | --- | --- |
| `url` | yes | The page address, `http` or `https` only, including query and fragment. |
| `title` | no | The tab title, whitespace collapsed, at most 300 characters. Left out when empty. |
| `selection` | no | The selected text, trimmed, line breaks kept as `\n`. At most 2,000 characters. Left out when nothing is selected or the page was saved whole. |
| `truncated` | no | `1` when the selection was longer than what was sent. Left out otherwise. |

- Every value is percent-encoded as UTF-8 with `encodeURIComponent`. A space
  is `%20`, never `+`, so `URLComponents.queryItems` decodes it as is.
- Parameters appear in the order above, each at most once.
- Lengths are counted in Unicode code points, so a character is never cut
  in half.
- The whole link stays under 8,000 characters. Text that grows a lot when
  encoded (Chinese, Japanese, emoji) is cut further to fit, and `truncated=1`
  is set.
- When `selection` is present the user asked for that passage; the app
  decides whether to store it as a highlight on the saved article or as a
  clip. When `truncated=1`, the app has the page address and the start of the
  passage, and can find the rest in the fetched article.
- Treat every value as untrusted input: any web page or other app can open a
  `coreader://save` link.

The limits live in [`link.js`](link.js).

## Privacy and permissions

| Permission | Why |
| --- | --- |
| `activeTab` | Read the address, title and selection of the tab you invoke the extension on, at that moment only. |
| `scripting` | Read the selected text with its line breaks (`window.getSelection()`), in that same tab. |
| `contextMenus` | The two right-click items. |

No host permissions, no content scripts, no network requests, no analytics,
no remote code, no storage.

## Files

| File | What |
| --- | --- |
| `manifest.json` | Manifest V3. |
| `link.js` | Builds the `coreader://save` link. No browser APIs. |
| `save.js` | Reads the selection and opens the link (`chrome.tabs.update`). |
| `background.js` | Service worker: context menu and shortcuts. |
| `popup.html`, `popup.css`, `popup.js` | The toolbar panel. |
| `icons/` | 16, 32, 48 and 128 px PNGs, drawn by `tools/make_icons.py`. |
| `test/link.test.mjs` | Tests for the link builder. |

```bash
npm run check    # node --check on every script
npm test         # node --test test/
uv run --with pillow python tools/make_icons.py   # redraw the icons
```

## Other browsers

- **Safari** cannot load this folder directly. It needs a Safari Web
  Extension target inside the Coreader Xcode project
  (`xcrun safari-web-extension-converter integrations/web-extension` makes a
  starting point), signed and shipped inside the app. Safari supports
  Manifest V3, the context menu and `scripting`. Opening a custom URL scheme
  from a Safari extension is the part to test; the dependable route there is
  native messaging to the containing app (`browser.runtime.sendNativeMessage`)
  with the same three values.
- **Firefox** would need `browser_specific_settings` and a
  `background.scripts` entry in place of the service worker.

## What was checked

- `manifest.json` parses, every script passes `node --check`, and the link
  builder's tests pass.
- Loaded unpacked into headless Chrome 158 with a throwaway profile: the
  extension loaded, its service worker started, the shortcut registered as
  ⌥⇧S, the panel rendered in light and dark, and the browser accepted the
  `coreader://save` navigation.

Not checked: the "Open Coreader?" prompt and the hand-off to the app (the
app does not register the scheme yet), the context menu and shortcut by hand
in a real window, and Arc, Brave and Edge.
