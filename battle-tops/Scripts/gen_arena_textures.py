"""
Arena texture generator.

Produces textures that line up exactly with the UVs emitted by gen_arena.py:

  arena_floor_albedo.png  - disc-mapped, centre at (0.5, 0.5), bowl edge on the
                            inscribed circle. Concentric contour rings, a danger
                            band near the wall, and a placeholder centre mark.
  arena_wall_albedo.png   - strip-mapped, U wraps once around, V runs 0 at the
                            bowl edge to 1 over the rim lip.

The ring spacing mirrors the bowl's parabolic profile: rings are drawn at
constant *height* intervals, so they bunch together where the slope is steep.
That turns the floor into a contour map and makes the bowl's depth readable
from directly above, which a flat colour cannot do.
"""

import math
import os

from PIL import Image, ImageDraw, ImageFilter

OUTPUT = "/mnt/user-data/outputs"

SIZE = 2048                  # floor texture is square
WALL_W, WALL_H = 2048, 256   # wall strip

# Geometry, mirroring gen_arena.py so markings land in the right places.
RIM_R = 0.190
BOWL_R = 0.1583
BOWL_EDGE_Y = 0.0143
PARA_K = BOWL_EDGE_Y / (BOWL_R ** 2)

# Gameplay radii, so the danger band sits where it actually matters.
MAX_RPM_SCALE = 0.70         # where orbits sit at full RPM
TOP_RADIUS = 0.024

# ── Palette: dark neutral ────────────────────────────────────────────────────
FLOOR_BASE = (26, 27, 30)
FLOOR_MID = (34, 36, 40)         # subtle radial variation
RING_MINOR = (52, 55, 62)
RING_MAJOR = (86, 91, 102)
CENTRE_MARK = (64, 68, 78)
DANGER_DARK = (58, 42, 20)
DANGER_STRIPE = (140, 96, 28)
WALL_BASE = (22, 23, 26)
WALL_ACCENT = (70, 74, 84)
WALL_TOP_EDGE = (120, 126, 138)


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def make_floor():
    """
    Floor texture, drawn in UV space.

    A pixel at distance `d` from the image centre corresponds to a point on the
    bowl at radius `d / 0.5 * BOWL_R`, since the mesh maps the bowl edge to the
    inscribed circle.
    """
    img = Image.new("RGB", (SIZE, SIZE), FLOOR_BASE)
    px = img.load()
    half = SIZE / 2

    # Height at which each contour ring is drawn, evenly spaced in Y.
    n_rings = 9
    ring_radii = []
    for k in range(1, n_rings + 1):
        y = BOWL_EDGE_Y * k / n_rings
        r = math.sqrt(y / PARA_K)
        ring_radii.append((r, k))

    danger_inner = BOWL_R * MAX_RPM_SCALE + TOP_RADIUS

    for py in range(SIZE):
        dy = (py - half) / half          # -1..1
        for pxx in range(SIZE):
            dx = (pxx - half) / half
            d = math.hypot(dx, dy)       # 0 at centre, 1 at image edge

            if d > 1.0:
                continue                 # corners, never sampled

            r = d * BOWL_R               # world radius this pixel represents

            # Base: very subtle darkening toward the rim, so the bowl reads as
            # concave even before the rings are applied.
            shade = min(d, 1.0) ** 1.6
            col = lerp(FLOOR_BASE, FLOOR_MID, shade * 0.8)

            # Danger band, blended rather than hard-edged.
            if r > danger_inner:
                t = min((r - danger_inner) / max(BOWL_R - danger_inner, 1e-6), 1.0)
                col = lerp(col, DANGER_DARK, t * 0.85)

            px[pxx, py] = col

    draw = ImageDraw.Draw(img)

    # Hazard striping across the danger band, so it reads at a glance rather
    # than as a subtle tint. Diagonal in UV space means the stripes appear to
    # sweep around the ring.
    n_stripes = 48
    for i in range(n_stripes):
        if i % 2:
            continue
        a0 = 2 * math.pi * i / n_stripes
        a1 = 2 * math.pi * (i + 1) / n_stripes
        r_in = (danger_inner / BOWL_R) * half
        r_out = half * 0.995
        pts = []
        steps = 4
        for k in range(steps + 1):
            a = a0 + (a1 - a0) * k / steps
            pts.append((half + r_in * math.cos(a), half + r_in * math.sin(a)))
        for k in range(steps, -1, -1):
            a = a0 + (a1 - a0) * k / steps
            pts.append((half + r_out * math.cos(a), half + r_out * math.sin(a)))
        draw.polygon(pts, fill=DANGER_STRIPE)

    # Contour rings, at constant height intervals.
    for r, k in ring_radii:
        rad_px = (r / BOWL_R) * half
        major = (k % 3 == 0)
        colour = RING_MAJOR if major else RING_MINOR
        width = 5 if major else 3
        draw.ellipse(
            [half - rad_px, half - rad_px, half + rad_px, half + rad_px],
            outline=colour, width=width,
        )

    # Radial ticks, to give rotation something to register against.
    n_ticks = 24
    for i in range(n_ticks):
        a = 2 * math.pi * i / n_ticks
        long_tick = (i % 6 == 0)
        r0 = BOWL_R * (0.80 if long_tick else 0.90)
        r1 = BOWL_R * 0.985
        x0 = half + (r0 / BOWL_R) * half * math.cos(a)
        y0 = half + (r0 / BOWL_R) * half * math.sin(a)
        x1 = half + (r1 / BOWL_R) * half * math.cos(a)
        y1 = half + (r1 / BOWL_R) * half * math.sin(a)
        draw.line([x0, y0, x1, y1],
                  fill=DANGER_STRIPE if long_tick else RING_MINOR,
                  width=7 if long_tick else 4)

    # Centre mark: a placeholder for a logo. Concentric arcs with gaps, so it
    # reads as deliberate rather than as an unfinished blank.
    for rr, w in ((0.055, 6), (0.085, 4), (0.115, 3)):
        rad_px = (rr / BOWL_R) * half
        box = [half - rad_px, half - rad_px, half + rad_px, half + rad_px]
        for start in (20, 110, 200, 290):
            draw.arc(box, start, start + 50, fill=CENTRE_MARK, width=w)

    # Soften slightly so the markings don't alias when the camera is close.
    img = img.filter(ImageFilter.GaussianBlur(radius=1.1))
    return img


def make_wall():
    """
    Wall strip. V=0 at the bowl edge, V=1 over the rim lip, so vertical
    position in the image maps directly to height up the wall.
    """
    img = Image.new("RGB", (WALL_W, WALL_H), WALL_BASE)
    draw = ImageDraw.Draw(img)

    # Vertical gradient: darker at the base, lifting toward the lip.
    for y in range(WALL_H):
        t = y / (WALL_H - 1)
        col = lerp(WALL_BASE, lerp(WALL_BASE, WALL_ACCENT, 0.55), t ** 0.7)
        draw.line([(0, y), (WALL_W, y)], fill=col)

    # Bright edge along the rim lip, which catches the light and defines the
    # boundary a top must clear to be knocked out.
    lip = int(WALL_H * 0.86)
    draw.rectangle([0, lip, WALL_W, WALL_H], fill=WALL_TOP_EDGE)
    draw.line([(0, lip), (WALL_W, lip)], fill=(200, 206, 218), width=3)

    # Vertical ribs, aligned to the same 24 divisions as the floor ticks.
    n_ribs = 24
    for i in range(n_ribs):
        x = int(WALL_W * i / n_ribs)
        draw.rectangle([x - 4, 0, x + 4, lip], fill=WALL_ACCENT)

    img = img.filter(ImageFilter.GaussianBlur(radius=0.8))
    return img


os.makedirs(OUTPUT, exist_ok=True)

floor = make_floor()
floor_path = os.path.join(OUTPUT, "arena_floor_albedo.png")
floor.save(floor_path)
print(f"Saved {floor_path}  ({floor.size[0]}x{floor.size[1]})")

wall = make_wall()
wall_path = os.path.join(OUTPUT, "arena_wall_albedo.png")
wall.save(wall_path)
print(f"Saved {wall_path}  ({wall.size[0]}x{wall.size[1]})")

danger_inner = BOWL_R * MAX_RPM_SCALE + TOP_RADIUS
print(f"\nDanger band starts at r={danger_inner:.4f} "
      f"({danger_inner / BOWL_R:.2f} of bowl radius)")
print(f"Contour rings at constant height steps of {BOWL_EDGE_Y / 9:.5f}")
