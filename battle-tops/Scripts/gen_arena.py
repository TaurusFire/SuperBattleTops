"""
Beyblade stadium generator.

Y-up, emitted directly at the scale the Godot project uses: outer rim radius
0.19, matching `arena_radius`. Tips of the tops sit at Y=0 on the bowl surface.

Three material groups, so Godot gets three surfaces:
  Floor - the parabolic bowl, UV-mapped as a disc so a centred logo works
  Wall  - the inner wall and rim lip, UV-mapped as a strip
  Shell - the outer casing and base, rarely seen

UV layout
---------
Floor: polar-to-square. The bowl centre maps to (0.5, 0.5) and the bowl edge
to the inscribed circle of the texture, so a square image with a logo in the
middle lands centred and undistorted. Radial distance is linear in texture
space, meaning concentric rings in the image appear as concentric rings on
the bowl — useful for reading height, since the bowl's slope means equal
radial steps are increasingly steep.

Wall: U wraps once around the circumference, V runs from the bowl edge (0) up
over the rim lip (1). A tiling strip texture works here.
"""

import math
import os

OUTPUT = "/mnt/user-data/outputs"

SEGS = 96

# -- Dimensions, in the same units as the Godot project ----------------------
RIM_R = 0.190            # outer radius; matches arena_radius
BOWL_R = 0.1583          # parabolic bowl extent
WALL_TOP_R = 0.1632      # top of the inner wall
WALL_TOP_Y = 0.076       # wall height above the bowl centre
SHELL_BOT_Y = -0.008     # underside of the outer casing

BOWL_RINGS = 28
# Chosen so the bowl edge sits at a sensible depth: y = K * r^2
BOWL_EDGE_Y = 0.0143
PARA_K = BOWL_EDGE_Y / (BOWL_R ** 2)


class OBJMesh:
    def __init__(self):
        self.verts = []
        self.uvs = []
        self.faces = []          # (vertex_idx, uv_idx) pairs, plus material
        self.mat = None

    def use(self, name):
        self.mat = name

    def v(self, x, y, z):
        self.verts.append((x, y, z))
        return len(self.verts) - 1

    def vt(self, u, v):
        self.uvs.append((u, v))
        return len(self.uvs) - 1

    def f(self, *pairs):
        """Each argument is a (vertex_index, uv_index) tuple."""
        self.faces.append((tuple(pairs), self.mat))

    # -- ring builders -------------------------------------------------------

    def ring_disc_uv(self, radius, y, uv_radius):
        """
        A ring of vertices with disc-projected UVs.

        `uv_radius` is where this ring lands in texture space, 0 at the centre
        and 0.5 at the edge of the inscribed circle.
        """
        out = []
        for i in range(SEGS):
            a = 2 * math.pi * i / SEGS
            ca, sa = math.cos(a), math.sin(a)
            vi = self.v(radius * ca, y, radius * sa)
            ui = self.vt(0.5 + uv_radius * ca, 0.5 + uv_radius * sa)
            out.append((vi, ui))
        return out

    def ring_strip_uv(self, radius, y, v_coord):
        """
        A ring with strip UVs: U wraps once around, V is fixed.

        Emits SEGS+1 UV columns so the seam closes without the texture
        reversing across the last quad.
        """
        out = []
        for i in range(SEGS):
            a = 2 * math.pi * i / SEGS
            vi = self.v(radius * math.cos(a), y, radius * math.sin(a))
            ui = self.vt(i / SEGS, v_coord)
            out.append((vi, ui))
        # Duplicate UV for the wrap-around column.
        seam_uv = self.vt(1.0, v_coord)
        return out, seam_uv

    # -- surface builders ----------------------------------------------------

    def connect_disc(self, lower, upper, flip=False):
        """Quad band between two disc-UV rings."""
        n = len(lower)
        for i in range(n):
            j = (i + 1) % n
            a, b = lower[i], lower[j]
            c, d = upper[j], upper[i]
            if flip:
                self.f(a, d, c, b)
            else:
                self.f(a, b, c, d)

    def connect_strip(self, lower, lower_seam, upper, upper_seam, flip=False):
        """Quad band between two strip-UV rings, closing the UV seam."""
        n = len(lower)
        for i in range(n):
            j = (i + 1) % n
            last = (j == 0)
            a = lower[i]
            b = (lower[j][0], lower_seam) if last else lower[j]
            c = (upper[j][0], upper_seam) if last else upper[j]
            d = upper[i]
            if flip:
                self.f(a, d, c, b)
            else:
                self.f(a, b, c, d)

    def fan_disc(self, centre, ring, flip=False):
        n = len(ring)
        for i in range(n):
            j = (i + 1) % n
            if flip:
                self.f(centre, ring[j], ring[i])
            else:
                self.f(centre, ring[i], ring[j])

    # -- output --------------------------------------------------------------

    def save(self, path, name, materials):
        mtl_file = os.path.splitext(os.path.basename(path))[0] + ".mtl"
        with open(os.path.join(os.path.dirname(path), mtl_file), "w") as mf:
            mf.write(f"# {name} materials\n")
            for mat, (kd, ks, ns) in materials.items():
                mf.write(f"newmtl {mat}\n")
                mf.write(f"Kd {kd[0]:.3f} {kd[1]:.3f} {kd[2]:.3f}\n")
                mf.write(f"Ks {ks[0]:.3f} {ks[1]:.3f} {ks[2]:.3f}\n")
                mf.write(f"Ns {ns}\n")
                mf.write(f"# map_Kd {mat.lower()}_albedo.png\n\n")

        grouped = {}
        for face, mat in self.faces:
            grouped.setdefault(mat, []).append(face)

        with open(path, "w") as f:
            f.write(f"# {name} — Y-up, arena-scale units (rim radius {RIM_R})\n")
            f.write(f"mtllib {mtl_file}\n")
            f.write(f"o {name}\n")
            for x, y, z in self.verts:
                f.write(f"v {x:.6f} {y:.6f} {z:.6f}\n")
            for u, v in self.uvs:
                f.write(f"vt {u:.6f} {v:.6f}\n")
            for mat, faces in grouped.items():
                f.write(f"usemtl {mat}\n")
                for face in faces:
                    parts = " ".join(f"{vi + 1}/{ui + 1}" for vi, ui in face)
                    f.write(f"f {parts}\n")

        counts = {m: len(fs) for m, fs in grouped.items()}
        print(f"{name}: {len(self.verts)} verts, {len(self.uvs)} uvs, "
              f"{sum(counts.values())} faces")
        for m, c in counts.items():
            print(f"    {m:6s} {c} faces")


m = OBJMesh()

# ── 1. Bowl floor ─────────────────────────────────────────────────────────────
# Parabolic, y = K r². Disc UVs so a square texture maps centred; the outer
# ring lands at 0.5 from centre, the inscribed circle of the image.
m.use("Floor")
prev = None
centre = None
for ri in range(BOWL_RINGS + 1):
    r = ri * BOWL_R / BOWL_RINGS
    y = PARA_K * r * r
    uv_r = 0.5 * (r / BOWL_R)
    if ri == 0:
        centre = (m.v(0.0, y, 0.0), m.vt(0.5, 0.5))
    else:
        cur = m.ring_disc_uv(r, y, uv_r)
        if ri == 1:
            m.fan_disc(centre, cur, flip=True)
        else:
            m.connect_disc(prev, cur, flip=False)
        prev = cur
bowl_edge = prev

# ── 2. Inner wall and rim lip ────────────────────────────────────────────────
# Strip UVs: V runs 0 at the bowl edge to 1 over the lip, so a tiling band
# texture reads correctly up the wall.
m.use("Wall")

# Re-emit the bowl edge with strip UVs, since it needs different texture
# coordinates from the same positions used by the floor.
wall_bot, wall_bot_seam = m.ring_strip_uv(BOWL_R, BOWL_EDGE_Y, 0.0)

wall_mid_r = BOWL_R + (WALL_TOP_R - BOWL_R) * 0.4
wall_mid_y = BOWL_EDGE_Y + (WALL_TOP_Y - BOWL_EDGE_Y) * 0.5
wall_mid, wall_mid_seam = m.ring_strip_uv(wall_mid_r, wall_mid_y, 0.45)
wall_top, wall_top_seam = m.ring_strip_uv(WALL_TOP_R, WALL_TOP_Y, 0.8)
rim, rim_seam = m.ring_strip_uv(RIM_R, WALL_TOP_Y, 1.0)

m.connect_strip(wall_bot, wall_bot_seam, wall_mid, wall_mid_seam, flip=False)
m.connect_strip(wall_mid, wall_mid_seam, wall_top, wall_top_seam, flip=False)
m.connect_strip(wall_top, wall_top_seam, rim, rim_seam, flip=False)

# ── 3. Outer shell and base ──────────────────────────────────────────────────
m.use("Shell")
shell_bot, shell_bot_seam = m.ring_strip_uv(RIM_R, SHELL_BOT_Y, 0.0)
m.connect_strip(rim, rim_seam, shell_bot, shell_bot_seam, flip=False)

base_centre = (m.v(0.0, SHELL_BOT_Y, 0.0), m.vt(0.5, 0.5))
base_ring = m.ring_disc_uv(RIM_R, SHELL_BOT_Y, 0.5)
m.fan_disc(base_centre, base_ring, flip=False)

m.save(
    os.path.join(OUTPUT, "arena.obj"), "Arena",
    {
        "Floor": ((0.62, 0.63, 0.66), (0.20, 0.20, 0.20), 24),
        "Wall":  ((0.42, 0.44, 0.48), (0.55, 0.55, 0.55), 64),
        "Shell": ((0.22, 0.22, 0.25), (0.15, 0.15, 0.15), 16),
    },
)

print(f"\nDimensions:")
print(f"  Rim radius   : {RIM_R:.4f}")
print(f"  Bowl radius  : {BOWL_R:.4f}")
print(f"  Bowl depth   : {BOWL_EDGE_Y:.4f}  (centre y=0, edge y={BOWL_EDGE_Y:.4f})")
print(f"  Wall top     : {WALL_TOP_Y:.4f}")
