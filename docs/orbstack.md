# OrbStack notes

This setup runs under [OrbStack](https://orbstack.dev) as the Docker engine on
macOS. Nothing here is OrbStack-exclusive — it would work on Docker Desktop — but
a few OrbStack behaviors it relies on are worth recording.

## Why OrbStack

- Lightweight, fast-starting Docker/Linux VM on macOS; the launcher can
  `open -gja OrbStack` and have Docker ready within seconds.
- Bind mounts map file ownership to the Mac user and honor Unix mode bits
  (verified: a `chmod 600` file created in the container reports `0600` on the
  Mac side). This matters because the GNOME keyring stores files with `600`/`700`
  permissions; if mode bits were flattened, the keyring could refuse to unlock.

## Bind mount

`compose.yaml` mounts `~/VM_Workspace` on the Mac to `/home/dev` in the
container — the container user's entire home. This is deliberate: sign-in, the
keyring, `~/.claude`, MCP config, and projects all live on the Mac and survive
container rebuilds. Keep the Docker **build context** out of that folder; the
build files live in the `_host/` subfolder (`~/VM_Workspace/_host`) so the build
context is just `_host`, not the whole home with its secrets.

## Networking

- The container's xpra server binds `0.0.0.0:14500`; compose maps it to
  `127.0.0.1:14500` on the Mac, so only the Mac can reach it.
- The container needs its own route to the Claude API, which OrbStack provides by
  default. No extra configuration.
- If an MCP server in the container ever needs to reach something on the Mac, use
  `host.orb.internal` from inside the container (OrbStack's host alias).

## OrbStack machines vs. this container

OrbStack also offers "machines" (full Linux VMs) with a built-in SSH server
registered as the `orb` host. This project does **not** use an OrbStack machine;
it uses a normal Docker container via Compose. The OrbStack docs note that
graphical apps are not officially supported and suggest X11 forwarding with
XQuartz — this project uses xpra instead, which is far better for the Electron
app (HiDPI, clipboard, notifications, per-window forwarding). See
`xpra-findings.md`.

### Aside: Claude Desktop's own SSH remote sessions

Claude Desktop has a built-in "SSH remote sessions" feature that runs the Claude
Code engine on a remote Linux/macOS host over SSH while the native Mac app is the
UI. It was **rejected for this use case** because that session still uses the Mac
app's signed-in account — it does not give a second, independent account. If you
only wanted an isolated *environment* (not a separate account), that feature,
pointed at an OrbStack machine, would be the lighter path and needs no xpra.

## Starting OrbStack from the launcher

`ClaudeBlack.sh` runs `open -gja OrbStack` if `docker info` fails, then polls
`docker info` for up to 90 seconds. `-g` keeps it in the background (no window
steal), `-j` launches hidden, `-a` names the app. If OrbStack is slow to start on
a cold boot, raise that timeout.
