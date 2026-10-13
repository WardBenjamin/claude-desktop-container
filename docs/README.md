# Claude Black: a completely isolated Claude Desktop on macOS

Run a completely isolated second instance of Claude Desktop on one Mac, with its
own home, keyring, and configuration. The Linux beta of Claude Desktop runs
inside a Docker container under OrbStack and is displayed on the Mac through
xpra, so you get the graphical Desktop frontend in that sandbox rather than only
the CLI. A re-badged xpra client, `/Applications/Claude Black.app`, launches the
whole stack and presents the app as its own native-feeling window.

## Why this exists

Claude Desktop's built-in SSH remote sessions share the Mac app's signed-in
account, so they cannot give a second, independent account. The only way to get
true separation is a second app instance with its own home, keyring, and MCP
configuration. Running the Linux build in a container and viewing it over xpra
delivers that.

## Architecture at a glance

```
  macOS host                              Docker container (OrbStack, Debian 13)
  ----------                              -------------------------------------
  Claude Black.app                        xpra server (:100, Xvfb)
   stub -> ClaudeBlack.sh  --- TCP ----->  bind-tcp 0.0.0.0:14500
   (xpra client, 6.5.4)      14500         |
                                           +-- claude-session (start-child)
                                                 gnome-keyring-daemon
                                                 claude-desktop (Electron, Linux beta)
  ~/VM_Workspace  <--- bind mount --->  /home/dev   (sign-in, ~/.claude, MCP, projects)
```

- The **server** (xpra + Claude Desktop) runs in the container. Every file read,
  shell command, and MCP server runs there.
- The **client** (xpra, the macOS app) is only the display and input surface.
- The container's entire home is the Mac folder `~/VM_Workspace`, so sign-in,
  keyring, `~/.claude`, and projects all persist on the Mac and survive rebuilds.

## Quick start

```sh
# 1. Build the image and start the container
~/VM_Workspace/_host/up.sh

# 2. Build and install the macOS app (downloads the xpra client, ~65 MB)
~/VM_Workspace/_host/build-app.sh

# 3. Launch it
open -a "Claude Black"
```

After that, `open -a "Claude Black"` (or the Dock icon) is all you need; the app
starts OrbStack and the container itself if they are not already up.

## File map (`~/VM_Workspace/_host`)

| File | Purpose |
|------|---------|
| `Dockerfile` | The container image: Claude Desktop + xpra server + dev tools, plus server-side patches. |
| `compose.yaml` | Compose project `claude-work`: port 14500, the `~/VM_Workspace` bind mount. |
| `up.sh` | Build (if needed) and start the container. |
| `build-app.sh` | Assemble, patch, sign, and install `/Applications/Claude Black.app`. |
| `assets/claude-black.png` | The app logo (original greyscale burst mark), used by the build. |
| `tools/make-logo.py` | Regenerates the logo (pure-stdlib Python, no dependencies). |
| `docs/` | This documentation. |

## Documentation

- [`container.md`](container.md) — the Docker image: build, use, modify, and every server-side patch and why.
- [`macos-app.md`](macos-app.md) — building, packaging, signing, and installing the macOS app; the launcher, icon, and stub.
- [`orbstack.md`](orbstack.md) — OrbStack-specific behavior this setup relies on.
- [`xpra-findings.md`](xpra-findings.md) — xpra research: HiDPI/Retina, the resize limitation, references, and fork feasibility.
- [`troubleshooting.md`](troubleshooting.md) — known issues, their causes, and fixes.

## Known limitations (see troubleshooting.md and xpra-findings.md)

- **Window resize does not work** (edge-drag or macOS tiling hotkeys). Fullscreen
  toggle is the only sizing control. This is a GTK-on-Quartz / frameless-Electron
  limitation, independent of display scaling.
- **The Finder / launch / quit icon** stays the old xpra icon due to a root-owned
  system icon cache. The Dock icon at runtime is correct.
- **The cursor changes size** over the window pane (xpra forwards the container
  cursor at the 2x virtual-screen scale).
- **Text is kept crisp** via a `--desktop-scaling=0.5` + `--force-device-scale-factor=2`
  hack; this is the trade that also causes the cursor scaling.
