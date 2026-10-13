#!/bin/zsh
# Build "/Applications/Claude Black.app": the xpra client re-badged as its own app, with a launcher that
# makes sure OrbStack and the container are up, centers the window, then attaches. Re-run to rebuild.
set -euo pipefail
cd "$(dirname "$0")"
REPO="$PWD"
NAME="Claude Black"
APP="/Applications/$NAME.app"
DMG=https://xpra.org/dists/MacOS/arm64/Xpra-Light-arm64-6.5.4-r2.dmg   # arm64 only; matches the server's 6.5.4

tmp=$(mktemp -d)

# cache the xpra client dmg so repeated builds do not re-download 65 MB.
# delete the cached file (or the whole .cache/) to force a fresh download.
CACHE="$REPO/.cache"; mkdir -p "$CACHE"
DMG_FILE="$CACHE/$(basename "$DMG")"
mount_dmg() { hdiutil attach "$1" -nobrowse -readonly -quiet -mountpoint "$tmp/mnt"; }
if [ ! -f "$DMG_FILE" ]; then
  echo "downloading $(basename "$DMG") ..."
  curl -fL "$DMG" -o "$DMG_FILE.part" && mv "$DMG_FILE.part" "$DMG_FILE"
fi
if ! mount_dmg "$DMG_FILE"; then            # cached copy is corrupt/partial: re-fetch once
  echo "cached dmg did not mount; re-downloading ..."
  rm -f "$DMG_FILE"
  curl -fL "$DMG" -o "$DMG_FILE.part" && mv "$DMG_FILE.part" "$DMG_FILE"
  mount_dmg "$DMG_FILE"
fi
rm -rf "$APP"
cp -R "$tmp/mnt/Xpra-Light.app" "$APP"          # Xpra.app in the dmg is an empty template, ignore it
hdiutil detach "$tmp/mnt" -quiet

# --- icon from the committed, original Claude Black mark (no external/Anthropic asset) ---
LOGO="$REPO/assets/claude-black.png"   # regenerate with: python3 tools/make-logo.py assets/claude-black.png
mkdir "$tmp/icon.iconset"
for s in 16 32 128 256 512; do
  sips -z $s $s "$LOGO" --out "$tmp/icon.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$LOGO" --out "$tmp/icon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$tmp/icon.iconset" -o "$APP/Contents/Resources/ClaudeBlack.icns"
# xpra sets the Dock icon and window icon at runtime from these PNGs, so swap them too
for f in "$APP/Contents/Resources/share/icons/xpra.png" "$APP/Contents/Resources/share/xpra/icons/xpra.png"; do
  sips -z 256 256 "$LOGO" --out "$f" >/dev/null
done

# --- identity ---
P="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $NAME" -c "Set :CFBundleDisplayName $NAME" \
  -c "Set :CFBundleIdentifier com.blward.claude-black" -c "Set :CFBundleIconFile ClaudeBlack.icns" \
  -c "Set :CFBundleExecutable ClaudeBlack" "$P"

# native title bar so macOS can resize/tile: Electron reports its frameless window as undecorated, and the client
# then makes a borderless NSWindow with only a finicky invisible drag border. Decorate it (adds a thin second bar).
B="$APP/Contents/Resources/lib/python/xpra/client/gtk3/window/base.py"
sed -i '' 's|^        return metadata.boolget("decorations", True)$|        return True  # Claude Black: always decorate so macOS can resize/tile|' "$B"
grep -q "always decorate" "$B"

# free resize: drop the min/max size hints Electron forwards, so macOS tiling hotkeys resize instead of only moving
WW="$APP/Contents/Resources/lib/python/xpra/client/gtk3/window/window.py"
sed -i '' '/^        wh = Gdk.WindowHints$/a\
\        hints = {k: v for k, v in dict(hints).items()\
\                 if bytestostr(k) not in ("min_width", "min_height", "max_width", "max_height",\
\                                          "width_inc", "height_inc", "base_width", "base_height")}
' "$WW"
grep -q "min_aspect_ratio" "$WW"

# --- launcher ---
cat > "$APP/Contents/MacOS/ClaudeBlack.sh" <<'SH'
#!/bin/zsh
set -u
export PATH=/usr/local/bin:/opt/homebrew/bin:$PATH    # GUI launches get a minimal PATH; docker lives in /usr/local/bin
HOST=~/VM_Workspace/_host
BUNDLE="${0:A:h:h:h}"   # .../Claude Black.app

# 1. OrbStack
if ! docker info >/dev/null 2>&1; then
  open -gja OrbStack
  for i in {1..90}; do docker info >/dev/null 2>&1 && break; sleep 1; done
fi
# 2. container
docker compose -f "$HOST/compose.yaml" up -d >/dev/null 2>&1
for i in {1..60}; do nc -z localhost 14500 2>/dev/null && break; sleep 1; done

# 3. center the main window on the primary screen via Accessibility (one-time prompt: Claude Black -> System Events)
(
  for i in {1..90}; do
    osascript -l JavaScript -e '
      ObjC.import("CoreGraphics");   // not AppKit: importing AppKit makes this helper show up as a second Dock icon
      const p = Application("System Events").processes.byName("Claude Black");
      if (p.windows.length === 0) throw "no window yet";
      const w = p.windows[0], [ww, wh] = w.size();
      const b = $.CGDisplayBounds($.CGMainDisplayID()), top = 25;   // primary display, points; 25 = menu bar
      w.position = [Math.round((b.size.width - ww) / 2), Math.round(top + (b.size.height - top - wh) / 2)];
    ' >/dev/null 2>&1 && break
    sleep 1
  done
) &

# 4. attach (see _host/README notes on the flags)
#   opengl=force: GL backing presents at Retina scale; "yes" skips menus/tooltips and renders them soft via Cairo
#   system-tray=no: macOS 26 AppKit crashes tearing down xpra's menu-bar items on disconnect
#   encodings=rgb,png: lossless only on a local link
exec "$BUNDLE/Contents/MacOS/Xpra-Light" attach tcp://localhost:14500 \
  --opengl=force --desktop-scaling=0.5 --system-tray=no --encodings=rgb,png --title="Claude Black" "$@"
SH
chmod +x "$APP/Contents/MacOS/ClaudeBlack.sh"
# launchd refuses to spawn this bundle with a script as CFBundleExecutable, so the main executable is a tiny
# Mach-O stub that execs the script beside it (needs the Xcode Command Line Tools for clang).
cat > "$tmp/stub.c" <<'C'
#include <mach-o/dyld.h>
#include <stdio.h>
#include <unistd.h>
int main(int argc, char **argv) {
  char path[4096]; unsigned int n = sizeof path;
  if (_NSGetExecutablePath(path, &n) != 0) return 1;
  char script[4200]; snprintf(script, sizeof script, "%s.sh", path);
  char *args[argc + 2]; args[0] = "/bin/zsh"; args[1] = script;
  for (int i = 1; i < argc; i++) args[i + 1] = argv[i];
  args[argc + 1] = 0;
  execv("/bin/zsh", args); return 1;
}
C
clang -O2 -o "$APP/Contents/MacOS/ClaudeBlack" "$tmp/stub.c"

# all bundle edits must precede signing, or codesign is invalidated
rm -f "$APP/Contents/Resources/xpra.icns"   # no stale icon for Finder/LaunchServices to pick up
/usr/libexec/PlistBuddy -c "Set :CFBundleDocumentTypes:0:CFBundleTypeIconFile ClaudeBlack.icns" "$P" 2>/dev/null || true
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
codesign --force --deep --sign - "$APP" 2>/dev/null
rm -rf "$tmp"
# the plain Xpra-Light.app from the earlier setup is superseded; remove it unless it is still running
pgrep -f "Xpra-Light.app/Contents/MacOS" >/dev/null || rm -rf /Applications/Xpra-Light.app
echo "built $APP"
