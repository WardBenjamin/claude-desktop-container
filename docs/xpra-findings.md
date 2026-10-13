# Xpra findings: HiDPI, resize, and fork feasibility

This records what we learned about xpra on macOS, with sources, so the open
limitations are understood and revisitable.

## Setup summary

- **Server:** xpra 6.5.x (whatever the xpra.org Debian repo serves) inside the
  container, seamless mode, forwarding the single Claude Desktop (Electron) window.
- **Client:** Xpra-Light 6.5.4-r2 on macOS (arm64), build `v6.5.x`, commit
  `g537466d077`.
- Seamless mode is supported with a **macOS client** (our case). The "seamless not
  available on macOS" note in xpra docs refers to a macOS *server*, which we do
  not use.

## HiDPI / Retina: why the scaling hack is needed

**The problem.** macOS/Quartz reports logical points (e.g. 1728x1117 on this
Retina panel), not physical pixels. A forwarded Linux app renders at that logical
resolution and the Retina panel then upscales it, so text looks soft.

**The hack we use (and kept):**
- Container: Electron runs with `--force-device-scale-factor=2` (renders at 2x).
- Client: attach with `--desktop-scaling=0.5` (downscales the 2x render back to
  logical points) plus `--opengl=force`.

This is the community-known workaround, acknowledged by the xpra maintainer in
issue #4736. The maintainer explicitly cautions that `desktop-scaling` below 1
"can cause rendering inefficiencies," i.e. it is a workaround, not a clean fix.

**The three scaling combinations, all tested:**

| Electron render | Client downscale | Result |
|-----------------|------------------|--------|
| 2x | 0.5 (current) | Crisp, correct size, resize coords broken |
| 1x | none | Correct size, text soft/blurry |
| 2x | none | Crisp, but window larger than the screen |

Only `2x + 0.5` gives crisp text at the right size, so it is the one we keep.

## The native HiDPI fix exists but does not apply to us

- Issue **#1933** (native macOS Retina, closed July 2024 via commit `854f012`,
  continued in **#4167**) makes the client render crisp with **no flags**, because
  recent xpra targets macOS 12+ where `wantsBestResolutionOpenGLSurface` defaults
  to true. The mechanism: advertise *double* screen dimensions to the server,
  downscale coordinates for window operations, but paint OpenGL at full resolution.
- **But it only fires when shadowing a real Retina Mac desktop or with already
  high-res content.** Our session is a seamless forward from a Linux virtual X11
  display, which has no Retina concept. Verified empirically: with Electron at 2x
  and the client downscale removed, the client still reported the screen as
  1728x1117 with no doubling, so the 2x window came through at 2056 points — wider
  than the 1728-point screen (a giant window). The native double-dimension path
  never engaged.

## Current upstream status (newest word)

- Issue **#4775** (updated 2026-06-11) is the latest. The proper fix — expose the
  true per-monitor resolution to the server so no downscale is needed — is **still
  unfinished**. Groundwork commits `e11357c` (macOS monitor data) and `1687b7b`
  (per-monitor scale factors) have landed. The maintainer's plan: "overload the
  `desktop-scaling` (or `dpi`?) switch to tell the xpra client to expose the true
  resolution to the server," and notes the OpenGL backend will adapt more easily
  than Cairo.
- **Verified in our build:** `platform/darwin/gui.py`'s `get_workareas()` reads
  and *logs* `screen.backingScaleFactor()` but does **not** use it to advertise
  the true resolution. The sensor is wired in; the actuator is not. This exactly
  matches the June 2026 thread state.

**Signal to watch:** a future xpra release that connects that logged
`backingScaleFactor()` to `desktop-scaling`/`dpi`. When it ships, retest Claude
Black with the scaling flags removed — that release is the one likely to give
crisp text and (possibly) working resize together.

## The resize limitation is separate and deeper

Resize (edge-drag and macOS tiling hotkeys) **does not work**. Crucially, it
failed even in the 1x no-scaling config, so it is **not** caused by the scaling
hack. Two documented causes stack:

1. **Claude Desktop is a frameless Electron window.** Frameless Electron windows
   do not expose standard window-manager resize; on X11 they resize via Electron's
   own CSS `-webkit-app-region` border hit-testing, not the WM. When forwarded and
   decorated by GTK, that affordance never maps to GTK/Quartz window-edge resize.
2. **xpra size-hint handling is known-fragile.** The xpra tracker states WMs are
   free to ignore xpra's hints, "making it very difficult to get window resizing
   working perfectly," and that if a window maps as non-resizable, later
   `WM_SIZE_HINTS` updates are ignored; the client and server can disagree on
   resizability, resizing one side but not the other. This matches the observed
   "resized once, then stuck."

Because resize fails independent of scaling, the in-progress HiDPI coordinate
work would **not** fix resize for free.

## Fork feasibility (if you want to fix it fully)

Two separate problems; a fork addresses one cleanly and the other uncertainly.

**HiDPI half — moderately feasible.**
- Design is public (#4775) and groundwork is merged; your build already reads the
  backing scale factor.
- The coordinate-scaling machinery (`xscale`/`yscale`, `sx()`/`sp()`) already
  exists (it is what `desktop-scaling` uses).
- Pure Python client, fast iteration, and you know the exact files.
- Core change: advertise doubled dimensions, downscale coordinates for window
  operations, exempt the OpenGL paint path (so it stays full-res). For your narrow
  case (one Retina Mac, one display, backing scale 2.0, one OpenGL window) you can
  hardcode assumptions the general fix cannot.
- Effort: a narrow proof-of-concept is days to a couple of weeks. General,
  multi-monitor, mixed-DPI, Cairo-fallback, upstream-mergeable is weeks to months
  (that is the part the maintainer is grappling with).

**Resize half — deeper, possibly intractable.**
- Sits in GTK's Quartz backend and Electron's frameless handling, neither of which
  the maintainer is touching. Might need Electron-side cooperation you cannot patch
  from xpra.
- Do a focused spike first: instrument where a resize request dies between
  GTK-Quartz and the server. That answer gates whether a fork is worth it.

**Recommendation.** Prefer engaging on #4775 over a hard fork: the maintainer has
the design and did the groundwork, and a scoped PR for the OpenGL single-Retina
case could be welcomed and de-risks the coordinate-translation details. Fund the
resize spike before committing, because resize is the thing you cannot work around
today and the HiDPI work will not deliver it for free.

## References

- xpra #1933 — HiDPI awareness for macOS (fixed 2024): https://github.com/Xpra-org/xpra/issues/1933
- xpra #4167 — native Retina via wantsBestResolutionOpenGLSurface: https://github.com/Xpra-org/xpra/issues/4167
- xpra #4736 — blurry on macOS client, desktop-scaling workaround: https://github.com/Xpra-org/xpra/issues/4736
- xpra #4775 — current HiDPI work, scale-factor groundwork (newest): https://github.com/Xpra-org/xpra/issues/4775
- xpra trac #2137 — size-hint / WM hint handling: https://www.xpra.org/trac/ticket/2137
- Electron frameless windows: https://www.electronjs.org/docs/latest/tutorial/custom-window-styles
- Groundwork commits: 854f012, 121df4c, e11357c, 1687b7b
