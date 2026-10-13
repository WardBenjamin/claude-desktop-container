#!/usr/bin/env python3
"""Generate the Claude Black app logo: an original radiating 'wiggly burst' mark.

Pure stdlib (zlib + struct), so it runs with only /usr/bin/python3 — no PIL.
Outputs a 1024x1024 RGBA PNG: a set of spindle rays radiating from the center,
each with a gentle S-wiggle, on a neutral-grey rounded tile, in greyscale to suit
"Claude Black". This is an original mark in the general sunburst visual family,
not a reproduction of any brand logo. Edit the constants and re-run to tweak;
commit the resulting PNG so the build needs no renderer.
"""
import zlib, struct, math

N = 1024            # output size
SS = 3              # supersampling for anti-aliasing
S = N * SS

TILE  = (110, 110, 115)    # neutral grey tile
RAY   = (233, 233, 235)    # light rays
CORE  = (60, 60, 64)       # subtle darker center ("black")

CORNER = 0.22 * S
CX = CY = 0.50 * S
R_IN  = 0.050 * S          # rays start near the center
R_OUT = 0.400 * S          # and reach here
RAYS  = 11                 # odd count, distinct from any brand mark
STEP  = 2 * math.pi / RAYS
HALF  = 0.52 * STEP        # max angular half-width of a ray (at its waist)
WIGGLE_AMP  = 0.16 * STEP  # sideways wave amplitude
WIGGLE_FREQ = 2.4          # waves along the ray's length
CORE_R = 0.072 * S         # darker central dot

def in_rounded_rect(x, y, w, h, r):
    cx = min(max(x, r), w - r)
    cy = min(max(y, r), h - r)
    return (x - cx) ** 2 + (y - cy) ** 2 <= r * r

def angdiff(a, b):
    d = a - b
    while d > math.pi:  d -= 2 * math.pi
    while d < -math.pi: d += 2 * math.pi
    return d

def spindle(t):
    # t in [0,1] along the ray; 0 at inner end, 1 at outer tip.
    # pointed at both ends, widest a bit past the middle (teardrop).
    if t <= 0 or t >= 1:
        return 0.0
    return (math.sin(math.pi * t) ** 0.65) * (0.45 + 0.55 * t)

def sample(x, y):
    if not in_rounded_rect(x, y, S, S, CORNER):
        return None
    dx, dy = x - CX, y - CY
    r = math.hypot(dx, dy)
    if r <= CORE_R:
        return CORE
    if r < R_IN or r > R_OUT:
        return TILE
    phi = math.atan2(dy, dx)
    t = (r - R_IN) / (R_OUT - R_IN)
    w = HALF * spindle(t)
    if w <= 0:
        return TILE
    # nearest ray and its neighbours (wiggle can push the centerline over)
    k0 = round(phi / STEP)
    for k in (k0 - 1, k0, k0 + 1):
        center = k * STEP + WIGGLE_AMP * math.sin(WIGGLE_FREQ * math.pi * t)
        if abs(angdiff(phi, center)) <= w:
            return RAY
    return TILE

rows = []
for oy in range(N):
    row = bytearray()
    for ox in range(N):
        r = g = b = a = 0
        for sy in range(SS):
            for sx in range(SS):
                c = sample(ox * SS + sx + 0.5, oy * SS + sy + 0.5)
                if c is None:
                    continue
                r += c[0]; g += c[1]; b += c[2]; a += 255
        n = SS * SS
        row += bytes((round(r / n) if a else 0,
                      round(g / n) if a else 0,
                      round(b / n) if a else 0,
                      round(a / n)))
    rows.append(bytes(row))

def chunk(tag, data):
    return (struct.pack(">I", len(data)) + tag + data +
            struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff))

raw = b"".join(b"\x00" + r for r in rows)
png = (b"\x89PNG\r\n\x1a\n" +
       chunk(b"IHDR", struct.pack(">IIBBBBB", N, N, 8, 6, 0, 0, 0)) +
       chunk(b"IDAT", zlib.compress(raw, 9)) +
       chunk(b"IEND", b""))

import sys
out = sys.argv[1] if len(sys.argv) > 1 else "assets/claude-black.png"
with open(out, "wb") as f:
    f.write(png)
print("wrote", out, N, "x", N)
