# Troubleshooting

Problems encountered during setup, their root causes, and fixes. Many are already
baked into the Dockerfile / build-app.sh; they are recorded here so the behavior
is understood if it resurfaces.

## Blank window (only a title bar, no content)

**Cause:** accumulated xpra server state from many rapid attach/detach cycles can
leave the window-source unable to forward the existing window to a new client (the
client log shows `log_windows_info(())` — empty). Not a code bug; normal
detach/reattach does not trigger it.

**Fix:**
```
docker compose -f ~/VM_Workspace/_host/compose.yaml restart
```
then relaunch the app. A fresh server start clears it.

## Sign-in does not persist / "No system keyring is available"

**Causes and fixes (all already in `claude-session`):**
- An **empty keyring password creates no keyring at all**, so sign-in is never
  saved. Fix: unlock the login keyring with a fixed password and write
  `~/.local/share/keyrings/default` = `login`.
- Chromium's `safeStorage` picks the **"basic" (unencrypted) backend** when no
  desktop environment is advertised. Fix: `export XDG_CURRENT_DESKTOP=GNOME` and
  launch Electron with `--password-store=gnome-libsecret`.
- If it still fails, confirm `gnome-keyring` is installed and the Secret Service
  answers: `docker compose exec claude sh -c 'DISPLAY=:100 dbus-send --session
  --print-reply --dest=org.freedesktop.secrets /org/freedesktop/secrets
  org.freedesktop.DBus.Peer.Ping'`.

## Sign-in link does nothing / OAuth does not return to the app

**Cause:** when Firefox finishes OAuth it invokes the app's `.desktop` handler to
deliver the `claude://` link, which launches a second `claude-desktop` process.
Without the sandbox flags that process dies on a namespace error before handing
off the link.

**Fix (in the Dockerfile):** patch the `.desktop` `Exec=` lines to include
`--no-sandbox --disable-gpu --password-store=gnome-libsecret`. To force the
sign-in browser to open inside the container, the image installs `firefox-esr`
and `xdg-utils`; `xdg-open https://claude.ai/login` opens Firefox in the container.

## Opaque white halos around menus / tooltips; magenta flashes

**Cause (halos):** with the compositing-manager selection claimed, Chromium draws
popups as transparent ARGB windows; the macOS xpra client cannot composite those
alpha windows, so the shadow's bounding box shows as an opaque white halo.
**Fix:** drop the `_NET_WM_CM_S0` claim in `x11/wm.py` (in the Dockerfile).

**Cause (magenta flashes):** lossy/video encodings mishandling popup alpha and
colourspace. **Fix:** attach with `--encodings=rgb,png` (lossless only).

## xpra client crashes on disconnect (SIGSEGV in NSStatusBar)

**Cause:** macOS 26 AppKit faults tearing down xpra's forwarded menu-bar status
item when the client disconnects (`+[NSStatusBar systemStatusBar]` →
`objc_retain` on a freed object).
**Fix:** attach with `--system-tray=no` (in the launcher). Nothing to tear down.

## "you must install xpra-x11 to use seamless" (server crash-loop)

**Cause:** the `xpra` metapackage only *recommends* `xpra-x11`, which contains
seamless mode.
**Fix:** install the server pieces explicitly (done in the Dockerfile):
`xpra-server xpra-x11 xpra-codecs python3-dbus xvfb dbus-x11`.

## Client errors `FileNotFoundError: ... os.getcwd()`

**Cause:** xpra calls `getcwd()` at startup; running it from a directory that was
deleted (e.g. an old scratch folder) fails.
**Fix:** the launcher does `cd "$(dirname "$0")"` first. If running the client by
hand, `cd ~` first.

## App will not launch: "Launchd job spawn failed" (POSIX 162)

**Cause:** launchd refuses a bundle whose `CFBundleExecutable` is a shell script.
**Fix:** `CFBundleExecutable` is a compiled Mach-O stub (`ClaudeBlack`) that
`execv`s `/bin/zsh` on `ClaudeBlack.sh`. Rebuild needs `clang` (Xcode Command Line
Tools). Removing `LSArchitecturePriority` alone did not help; the stub is required.

## Two Dock icons flash at startup

**Cause:** the window-centering helper imported AppKit; any process that loads
AppKit registers with the Dock as an app for as long as it runs.
**Fix:** the helper reads the screen via CoreGraphics
(`$.CGDisplayBounds($.CGMainDisplayID())`) instead of AppKit. (In the launcher.)

## Wrong icon in Finder / launch / quit animation (Dock icon is correct)

**Cause:** the bundle's `ClaudeBlack.icns` is correct grey (the Dock shows it at
runtime), but the **root-owned system icon cache** holds the original xpra icon
from when the bundle was first created. Repeated in-place rebuilds keep the same
path, so the cache persists.
**Status:** left unfixed (cosmetic). The user-level reset (`killall
iconservicesagent; lsregister -f; killall Dock Finder`) did not clear it.
**Fix if wanted (run in Terminal.app, not via a `!`-prefixed command — sudo needs
an interactive password prompt):**
```
sudo rm -rf /Library/Caches/com.apple.iconservices.store
sudo killall iconservicesd iconservicesagent
killall Dock Finder
```

## Cursor changes size over the window pane

**Cause:** xpra forwards the container's X11 cursor rendered at the 2x
virtual-screen scale.
**Option (not applied):** `--cursors=no` uses the native macOS cursor everywhere
but loses app-specific cursors (text I-beam, link pointer).

## Window resize does not work

Edge-drag and macOS tiling hotkeys do not resize; only fullscreen toggle works.
This is a GTK-on-Quartz / frameless-Electron limitation, independent of scaling
(it fails at 1x too). There is no known fix in the current xpra version. See
`xpra-findings.md` for the full analysis and what upstream change to watch for.

## Text is soft/blurry

Expected only if the scaling flags were removed. The crisp config needs **both**
`--force-device-scale-factor=2` (container, Electron) and `--desktop-scaling=0.5`
(client, attach). See `xpra-findings.md`.
