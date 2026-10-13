# syntax=docker/dockerfile:1
# Claude Desktop (Linux beta) + xpra, shown on macOS via the xpra client.
# Attach from the Mac:  xpra attach tcp://localhost:14500
FROM debian:trixie
ARG USER=dev
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl gnupg \
 && curl -fsSLo /usr/share/keyrings/claude-desktop-archive-keyring.asc https://downloads.claude.ai/claude-desktop/key.asc \
 && echo "deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/claude-desktop-archive-keyring.asc] https://downloads.claude.ai/claude-desktop/apt/stable stable main" > /etc/apt/sources.list.d/claude-desktop.list \
 && curl -fsSLo /usr/share/keyrings/xpra.asc https://xpra.org/xpra.asc \
 && curl -fsSLo /etc/apt/sources.list.d/xpra.sources https://raw.githubusercontent.com/Xpra-org/xpra/master/packaging/repos/trixie/xpra.sources \
 && apt-get update && apt-get install -y --no-install-recommends \
    # display + keyring (recommends skipped on purpose: claude-desktop's are Cowork's QEMU stack, useless in a container)
    xpra-server xpra-x11 xpra-codecs python3-dbus xvfb dbus-x11 gnome-keyring fonts-dejavu fonts-noto-color-emoji \
    claude-desktop firefox-esr xdg-utils \
    # dev tools: add yours here, or `sudo apt install` at runtime
    sudo git build-essential python3 python3-venv nodejs npm ripgrep jq less vim openssh-client xdotool \
 && rm -rf /var/lib/apt/lists/* \
 # the claude:// handler Firefox invokes must use the same sandbox flags or it dies before reaching the running app
 && sed -i 's|^Exec=claude-desktop|Exec=claude-desktop --no-sandbox --disable-gpu --password-store=gnome-libsecret|' /usr/share/applications/com.anthropic.Claude.desktop \
 # don't claim the compositing-manager selection: with it, Chromium draws menus/tooltips as transparent ARGB windows
 # whose shadows the macOS xpra client cannot composite (opaque white halos). Without it they are plain opaque popups.
 && sed -i 's|ManagerSelection("WM_S0", "_NET_WM_CM_S0")|ManagerSelection("WM_S0")|' /usr/lib/python3/dist-packages/xpra/x11/wm.py

RUN useradd -m -s /bin/bash $USER && echo "$USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$USER \
 && mkdir -m700 /run/user/1000 && chown $USER /run/user/1000

# Runs inside xpra's D-Bus session: unlock the login keyring with a fixed password and make it the default,
# so the app's sign-in persists across restarts without a prompt (an empty password creates no keyring at all).
# ponytail: --no-sandbox because Chromium's sandbox needs user namespaces Docker blocks; the container is the boundary.
# ponytail: renders for Retina; xpra's DPI sync is unreliable with Electron.
RUN cat > /usr/local/bin/claude-session <<'SH' && chmod +x /usr/local/bin/claude-session
#!/bin/sh
[ -e ~/.bashrc ] || cp /etc/skel/.bashrc /etc/skel/.profile ~   # first run on an empty bind-mounted home
mkdir -p ~/.local/share/keyrings && printf login > ~/.local/share/keyrings/default
eval "$(printf claude | gnome-keyring-daemon --unlock --daemonize --components=secrets)"
export XDG_CURRENT_DESKTOP=GNOME   # Chromium picks the keyring backend from this; without it safeStorage silently uses "basic"
exec claude-desktop --no-sandbox --disable-gpu --force-device-scale-factor=2 --password-store=gnome-libsecret "$@"
SH

# system-wide tools: the home dir is a bind mount from the Mac, so nothing baked into /home survives
RUN npm install -g @anthropic-ai/claude-code && curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh

USER $USER
WORKDIR /home/$USER
ENV XDG_RUNTIME_DIR=/run/user/1000 PATH=/home/$USER/.local/bin:$PATH

EXPOSE 14500
CMD ["xpra", "start", ":100", "--bind-tcp=0.0.0.0:14500", \
     "--start-child=claude-session", "--exit-with-children", "--daemon=no"]
