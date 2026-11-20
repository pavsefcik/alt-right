# Alt Right

A tiny macOS menu-bar app that puts the Finder shortcuts you keep googling behind one
right-click submenu.

| Command | What it does (the shortcut you'd normally press) |
| --- | --- |
| **Copy Path** | `⌥⌘C` — copies the POSIX path(s) of the selection |
| **Paste Path** | opens Finder's *Go to Folder* sheet and pastes the clipboard path |
| **Go to Folder** | `⇧⌘G` — opens Finder's *Go to Folder* sheet |
| **Connect to Server** | `⌘K` — opens Finder's *Connect to Server* dialog |
| **Search Bookmarks** | `⌥⌘B` — fuzzy-search saved folders, files and URLs |
| **Add Bookmark** | `⇧⌥⌘B` — saves the Finder selection, or a manual path/URL |
| **History** | `⌃⌘H` — every path you copy, ready to copy, open, or bookmark |

Right-click a file or folder → **Alt Right** gives you Copy Path, Paste Path, Search
Bookmarks, Add Bookmark and History. **Go to Folder** and **Connect to Server** live in the
menu-bar menu. *Paste Path* stops in *Go to Folder* instead of pressing Return, so you can
check the destination first.

**iCloud Drive, Google Drive, Dropbox and friends never show third-party Finder menus** —
that is an Apple limitation. Use the menu-bar icon there; the commands work the same way.

<img src="docs/settings.png" width="420" alt="The Alt Right info window">

## Bookmarks and History

- **Search Bookmarks** — type to filter by title, description or path; **Open**, **Edit**,
  **Delete**, or double-click a row. Newly added bookmarks appear at the top.
- **Edit** — correcting a stale path rewrites that bookmark in place (it does not leave the
  old one behind). **Browse…** opens a file panel when pasting a path is not what you want.
- **Add Bookmark** — pre-filled with the current Finder selection when invoked from the
  menu bar or its hot key (falling back to the last path Alt Right saw, then the clipboard).
  A multi-item Finder selection is added in one go, with file names as titles; existing
  paths are skipped.
- **Path input is forgiving** — quoted paths (`'…'`, `"…"`, curly quotes), a missing
  opening or closing quote, shell-escaped spaces (`My\ Folder`), `~`, `file://` URLs, and
  `smb://`/`afp://`/`cifs://`/`nfs://` URLs are all reduced to the local path they mean.
- **History** — records *every* path you copy: Alt Right's Copy Path, Finder's own `⌥⌘C`,
  and any absolute path copied from another app. The clipboard is polled about once a
  second and only accepted when every line is a path, so prose and code are ignored. Rows
  can be filtered, copied, opened, removed or turned into bookmarks.
- All three windows open on the desktop you are on, float over Finder, and close on Esc or
  a click outside. Double-click or Return opens a row, `⌘F` focuses the filter, `⌘O` opens.
- The `⌥⌘B`, `⇧⌥⌘B` and `⌃⌘H` shortcuts are registered as system-wide hot keys, so they
  work while Finder (or any other app) is frontmost — not just while a menu is open.
- In **Open Alt Right → Shortcuts**, click a combination and press a new one. The change is
  live immediately (global hot key, menu-bar menu, and the Finder submenu); **Restore
  Defaults** brings the three combinations above back.
- Data lives at `~/Library/Application Support/Alt Right/` (`bookmarks.json`,
  `history.json`) — plain JSON, never uploaded anywhere.

## Install

### From a GitHub release (another Mac)

Download the latest `.dmg` from
[Releases](https://github.com/pavsefcik/alt-right/releases), open it and drag **Alt Right**
into **Applications**. The build is signed ad-hoc and not notarized, so remove the download
quarantine once:

```bash
xattr -dr com.apple.quarantine "/Applications/Alt Right.app"
open "/Applications/Alt Right.app"
```

Then:

1. **Finder extension** — *System Settings › General › Login Items & Extensions › Finder
   Extensions* → enable **Alt Right**. If it is not listed:
   ```bash
   pluginkit -a "/Applications/Alt Right.app/Contents/PlugIns/AltRightFinderSync.appex"
   pluginkit -e use -i com.pavel.altright.FinderSync
   killall Finder
   ```
2. **Accessibility** — needed so the app can press `⇧⌘G` and `⌘K`. Open **Alt Right** from the
   menu bar and press **Grant…**, then turn the switch on by hand (macOS does not allow
   apps to do that).
3. **Automation** — macOS asks once when *Add Bookmark* reads the current Finder selection.
   Allow it.

Permissions are per signature: a freshly downloaded build has to be granted Accessibility
again.

### From source (this Mac)

```bash
./scripts/install.sh              # Release: builds, installs to /Applications, enables the extension
CONFIG=Debug ./scripts/install.sh # debug build
./scripts/uninstall.sh            # removes the app and its extension registration
./scripts/package.sh              # dist/  →  AltRight-<version>.dmg and .zip for other Macs
```

Keep only **one** copy of the app registered. Building from Xcode while an `/Applications`
copy exists makes macOS refuse the extension: *"An extension with the same bundle ID already
exists with a different path"*. `install.sh` unregisters every other copy it finds.

## How it works

```
Finder ─right-click─▶ AltRightFinderSync.appex (sandboxed)
                          ├─ Copy Path: writes the pasteboard itself
                          └─ altright://add-bookmark | search-bookmarks | open-history | paste-path
                                     ▼
                         Alt Right.app (unsandboxed helper)
```

A sandboxed extension cannot post keyboard events or read the app's Application Support
files, so it hands those actions to the app over a private URL scheme. The app re-registers
its `kAEGetURL` handler in `applicationDidFinishLaunching`, because SwiftUI installs its own
handler at startup and would swallow the events. The extension monitors `/`, the home
folder and every mounted volume (Finder treats each volume as a separate root), refreshing
the list on mount and unmount.

## Caveats

- Self-signed with a local identity — fine on your own Mac; shipping it needs a Developer ID
  certificate, hardened runtime and notarization.
- *Paste Path* pastes whatever is on the clipboard, like the real `⇧⌘G`; prose just beeps.
- Listing a volume makes Finder show the Alt Right icon for it in the sidebar — Finder's own
  behaviour for extension-enabled volumes.
- A *View › Customize Toolbar…* item ("Alt Right") is also registered.
- The UI is English only: `en.lproj` is generated by `scripts/gen_strings.py` from the
  `L("…")` keys in the sources.

## Layout

```
AltRight/                  menu-bar app (LSUIElement): settings UI, key actuation, windows
  Bookmarks/               stores, search/history/editor windows, URL payloads
  AppIcon.icns             generated by scripts/gen_icon.swift
AltRightFinderSync/        Finder Sync extension: submenu + handoff
scripts/                   install.sh, uninstall.sh, gen_strings.py, gen_icon.swift
```
