# The Docker container

The container runs the Linux beta of Claude Desktop plus an xpra server that
exports its window over TCP. It is built from `Dockerfile` and run via
`compose.yaml` (Compose project name `claude-work`).

## Build and run

```sh
cd ~/VM_Workspace/_host
./up.sh                       # docker compose up -d --build, then shows status
# or manually:
docker compose up -d --build
docker compose ps             # expect 127.0.0.1:14500->14500/tcp
docker compose logs -f        # xpra + Electron output
docker compose restart        # fresh xpra server + fresh Claude Desktop
docker compose stop           # stop for real (restart policy relaunches on quit)
docker compose down           # remove the container (the ~/VM_Workspace volume persists)
```

The macOS app calls `docker compose -f ~/VM_Workspace/_host/compose.yaml up -d`
itself, so you rarely run these by hand after the first build.

## Base image and packages

- **Base:** `debian:trixie` (Debian 13). Chosen over Ubuntu because Debian ships
  a real `firefox-esr`, which keeps the sign-in OAuth flow (and its `claude://`
  callback) inside the container instead of leaking to the Mac's browser.
  Anthropic's apt repo supports Ubuntu 22.04+/Debian 12+ on amd64 and arm64.
- **Claude Desktop:** installed from Anthropic's apt repository
  (`https://downloads.claude.ai/claude-desktop/apt/stable`). Recommends are
  skipped on purpose — the recommended packages are Cowork's QEMU/KVM stack,
  which is useless and heavy inside a container.
- **xpra:** installed from the xpra.org Debian repo. **Important:** the `xpra`
  metapackage only *recommends* `xpra-x11`, which holds seamless mode; installing
  the metapackage alone crash-loops with "you must install xpra-x11 to use
  seamless". The Dockerfile installs the server pieces explicitly:
  `xpra-server xpra-x11 xpra-codecs python3-dbus xvfb dbus-x11`.
- **Keyring:** `gnome-keyring` provides the Secret Service that Electron's
  `safeStorage` uses to persist sign-in.
- **Dev tools:** `git build-essential python3 python3-venv nodejs npm ripgrep jq
  less vim openssh-client xdotool`, plus `claude` (Claude Code CLI) and `uv`
  installed system-wide. `xdotool` is present for window scripting/debugging.

## Server-side patches baked into the image

These are applied by `sed` in the Dockerfile. Do not remove them without reading
why.

### 1. `claude://` handler sandbox flags
```
sed 's|^Exec=claude-desktop|Exec=claude-desktop --no-sandbox --disable-gpu --password-store=gnome-libsecret|' \
    /usr/share/applications/com.anthropic.Claude.desktop
```
When Firefox finishes OAuth it invokes the app's `.desktop` handler to deliver
the `claude://` link. Without the sandbox flags that second process dies on a
namespace error (Docker blocks the user namespaces Chromium's sandbox needs)
before it can hand the link to the running app, so sign-in never completes. The
handler must carry the same flags as the main launch.

### 2. Do not claim the X11 compositing-manager selection
```
sed 's|ManagerSelection("WM_S0", "_NET_WM_CM_S0")|ManagerSelection("WM_S0")|' \
    /usr/lib/python3/dist-packages/xpra/x11/wm.py
```
If xpra owns the `_NET_WM_CM_S0` selection, Chromium treats a compositing manager
as present and draws menus, tooltips, and dialogs as transparent ARGB popups with
drop shadows. The macOS xpra client **cannot composite those alpha windows**, so
every popup showed an opaque white halo around its shadow. Dropping the
compositing-manager claim makes Chromium fall back to plain opaque popups, which
render cleanly. Cost: menus lose their rounded-corner shadow styling (plain look).

## The start script: `claude-session`

`/usr/local/bin/claude-session` is the xpra `--start-child`. It:

1. Seeds `~/.bashrc`/`~/.profile` on first run (the home is an empty bind mount).
2. Writes `~/.local/share/keyrings/default` = `login` and unlocks the login
   keyring with the fixed password `claude`. **An empty password creates no
   keyring at all** (verified), so sign-in would not persist; a fixed password
   plus the `default` pointer makes the login keyring exist and auto-unlock.
3. Exports `XDG_CURRENT_DESKTOP=GNOME` so Chromium's `safeStorage` selects the
   libsecret backend instead of silently falling back to the unencrypted "basic"
   store (which triggers the "No system keyring available" banner).
4. Execs `claude-desktop` with:
   - `--no-sandbox` — Chromium's sandbox needs user namespaces Docker blocks; the
     container is the security boundary.
   - `--disable-gpu` — no GPU in the container; avoids Chromium trying to use one.
   - `--force-device-scale-factor=2` — renders at 2x so text is crisp on Retina
     (paired with the client's `--desktop-scaling=0.5`). See `xpra-findings.md`.
   - `--password-store=gnome-libsecret` — forces the libsecret keyring backend.

## The xpra server command (`CMD`)

```
xpra start :100 --bind-tcp=0.0.0.0:14500 --start-child=claude-session \
     --exit-with-children --daemon=no
```

- `:100` is the virtual X display (backed by Xvfb).
- `--bind-tcp=0.0.0.0:14500` is the client connection point; compose maps it to
  `127.0.0.1:14500` on the Mac only.
- `--exit-with-children` ties the server lifetime to Claude Desktop; quitting the
  app exits the container, and the `unless-stopped` restart policy relaunches it.

## Modifying the image

- **Add a dev tool:** append to the `apt-get install` dev-tools line, or just
  `sudo apt install <pkg>` at runtime inside the container (it has passwordless
  sudo). Runtime installs under `/usr` do **not** persist a rebuild, but anything
  under the home (`/home/dev`, i.e. `~/VM_Workspace`) does, including
  `npm i -g`, `uv tool install`, and MCP config.
- **Change an Electron/Chromium flag:** edit the `exec claude-desktop ...` line in
  the `claude-session` heredoc, then rebuild. For a quick test without a rebuild,
  edit `/usr/local/bin/claude-session` live (`docker compose exec -u root ...`)
  and `docker compose restart`.
- **Rebuild:** `./up.sh` or `docker compose up -d --build`.
- **Reset to a clean home:** `docker compose down` then move/clear
  `~/VM_Workspace` (this wipes sign-in and the keyring too).

## Persistence and durability

- The entire container home is `~/VM_Workspace` (bind mount). Sign-in,
  `.local/share/keyrings`, `.config/Claude`, and `~/.claude` all live there.
- OrbStack bind mounts map file ownership to the Mac user and honor Unix mode
  bits (verified: a `chmod 600` file in the container shows `0600` on the Mac),
  so the keyring's `700`/`600` permissions are preserved.
- Durability test: sign in, then `docker compose restart` and relaunch the app.
  Coming back signed in with no keyring prompt is the pass condition.
