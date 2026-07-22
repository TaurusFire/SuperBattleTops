"""
Beyblade-style top generator.

Builds three tops as OBJ + MTL, ready to drop into Godot:
  - Attack:  9 wide blades, aggressive silhouette
  - Stamina: 4 slim blades, tall narrow spindle
  - Defence: spoked ring (5 spokes), squat and wide

Conventions
-----------
Y-up, tip pointing down (-Y), disc centred on the origin's XZ plane.
Units match the arena: disc radius ~0.024 against an arena radius of 0.19.

Each top emits three material groups so Godot gets three surfaces:
  Rim   - the outer band of the disc (metallic)
  Body  - the disc's inboard surface (coloured)
  Tip   - the shaft below the disc (dark metal)

The Rim/Body split is what makes rotation legible: contrasting bands strobe
as the top spins, which reads as speed even with the visual spin capped.
"""

import math
import os

OUTPUT = "/mnt/user-data/outputs"

# Everything scales from this. Arena radius is 0.19; a top is ~1/8 of that.
R = 0.024


class OBJMesh:
    def __init__(self):
        self.verts = []
        self.faces = []          # (indices, material_name)
        self.mat = None

    # -- primitives ----------------------------------------------------------

    def v(self, x, y, z):
        self.verts.append((x, y, z))
        return len(self.verts) - 1

    def use(self, name):
        self.mat = name

    def f(self, *idx):
        self.faces.append((tuple(i + 1 for i in idx), self.mat))

    def ring(self, radii, y, segs):
        """A ring of vertices. `radii` is either a scalar or a per-segment list."""
        if not isinstance(radii, (list, tuple)):
            radii = [radii] * segs
        out = []
        for i in range(segs):
            a = 2 * math.pi * i / segs
            out.append(self.v(radii[i] * math.cos(a), y, radii[i] * math.sin(a)))
        return out

    def bridge(self, lower, upper, segs, flip=False):
        """Quad band between two rings of equal length."""
        for i in range(segs):
            n = (i + 1) % segs
            if flip:
                self.f(lower[i], lower[n], upper[n], upper[i])
            else:
                self.f(lower[i], upper[i], upper[n], lower[n])

    def cap(self, ring_idx, y, segs, up=True):
        """Fan-fill a ring with a centre vertex.

        Ring vertices run anticlockwise seen from +Y, so an upward-facing cap
        needs the reversed order for its normal to point up.
        """
        c = self.v(0.0, y, 0.0)
        for i in range(segs):
            n = (i + 1) % segs
            if up:
                self.f(c, ring_idx[n], ring_idx[i])
            else:
                self.f(c, ring_idx[i], ring_idx[n])

    # -- components ----------------------------------------------------------

    def shaft(self, r_top, r_tip, y_top, y_tip, segs=48, curve=0.0, rings=8):
        """
        Tapered shaft from the disc underside down to the contact point.

        `curve` bulges the profile outward (positive) or tucks it inward
        (negative) rather than tapering in a straight line. Around 0.3-0.5
        gives a rounded, ball-ended tip; 0 reproduces a plain cone.
        """
        if curve == 0.0 and rings <= 1:
            top = self.ring(r_top, y_top, segs)
            if r_tip < 1e-4:
                point = self.v(0.0, y_tip, 0.0)
                for i in range(segs):
                    n = (i + 1) % segs
                    self.f(top[i], point, top[n])
            else:
                bot = self.ring(r_tip, y_tip, segs)
                self.bridge(bot, top, segs)
                self.cap(bot, y_tip, segs, up=False)
            return

        # Subdivided profile, interpolating radius along a curved path.
        prev = None
        for k in range(rings + 1):
            t = k / rings                       # 0 at the tip, 1 at the top
            # Ease the radius so it swells near the base of the shaft.
            shaped = t ** (1.0 - curve) if curve < 1.0 else t
            r = r_tip + (r_top - r_tip) * shaped
            y = y_tip + (y_top - y_tip) * t
            if k == 0 and r < 1e-4:
                prev = None
                point = self.v(0.0, y, 0.0)
                continue
            cur = self.ring(r, y, segs)
            if prev is None and k == 0:
                self.cap(cur, y, segs, up=False)
            elif prev is None:
                for i in range(segs):
                    n = (i + 1) % segs
                    self.f(cur[i], point, cur[n])
            else:
                self.bridge(prev, cur, segs)
            prev = cur

    def torus_band(self, r_centre, r_tube, y_centre, segs=120, tube_segs=16,
                   arc_start=0.0, arc_end=2 * math.pi):
        """
        A ring with a circular cross-section — a torus.

        `r_centre` is the distance from the origin to the tube's centre line,
        `r_tube` the radius of the tube itself. The outer edge therefore sits
        at r_centre + r_tube.
        """
        rings = []
        for j in range(tube_segs):
            phi = arc_start + (arc_end - arc_start) * j / tube_segs
            r = r_centre + r_tube * math.cos(phi)
            y = y_centre + r_tube * math.sin(phi)
            rings.append(self.ring(r, y, segs))

        for j in range(tube_segs):
            a = rings[j]
            b = rings[(j + 1) % tube_segs]
            for i in range(segs):
                n = (i + 1) % segs
                self.f(a[i], b[i], b[n], a[n])

    def banded_disc(self, profile, segs, rim_name, body_name, rim_frac=0.72,
                    rim_bands=None, dome_height=0.0, dome_rings=6):
        """
        Disc of revolution from a profile of (radius, y) pairs.

        `profile` runs bottom to top. Faces are assigned to `rim_name` where the
        radius exceeds `rim_frac` of the maximum, and `body_name` inboard of it,
        which puts the material seam at a consistent radius rather than an
        arbitrary ring boundary.
        """
        def peak(r):
            if callable(r):
                return max(r(2 * math.pi * i / segs) for i in range(segs))
            return r

        max_r = max(peak(r) for r, _ in profile)
        rings = []
        for r, y in profile:
            if callable(r):
                radii = [r(2 * math.pi * i / segs) for i in range(segs)]
            else:
                radii = r
            rings.append((self.ring(radii, y, segs), radii, y))

        for k in range(len(rings) - 1):
            lower, lr, _ = rings[k]
            upper, ur, _ = rings[k + 1]
            if not isinstance(lr, (list, tuple)):
                lr = [lr] * segs
            if not isinstance(ur, (list, tuple)):
                ur = [ur] * segs
            for i in range(segs):
                n = (i + 1) % segs
                # Band belongs to the rim if either edge sits outboard of the seam.
                if rim_bands is not None:
                    is_rim = k in rim_bands
                else:
                    outer = max(lr[i], ur[i], lr[n], ur[n])
                    is_rim = outer > max_r * rim_frac
                self.use(rim_name if is_rim else body_name)
                self.f(lower[i], upper[i], upper[n], lower[n])

        # Close top and bottom.
        top_ring, top_r, top_y = rings[-1]
        bot_ring, bot_r, bot_y = rings[0]
        self.use(body_name)
        if dome_height > 0.0:
            # Quarter-ellipse from the top ring up to an apex, so the disc
            # bulges rather than ending flush.
            r_top = max(top_r) if isinstance(top_r, (list, tuple)) else top_r
            prev = top_ring
            for k in range(1, dome_rings + 1):
                t = k / dome_rings
                r = r_top * math.cos(t * math.pi * 0.5)
                y = top_y + dome_height * math.sin(t * math.pi * 0.5)
                if k == dome_rings:
                    apex = self.v(0.0, y, 0.0)
                    for i in range(segs):
                        n = (i + 1) % segs
                        self.f(apex, prev[n], prev[i])
                else:
                    nxt = self.ring(r, y, segs)
                    self.bridge(prev, nxt, segs)
                    prev = nxt
        else:
            self.cap(top_ring, top_y, segs, up=True)
        self.cap(bot_ring, bot_y, segs, up=False)

    def spoked_ring(self, r_inner, r_outer, hub_r, y0, y1, n_spokes, segs=120,
                    rim_name="Rim", body_name="Body", spoke_width=0.30,
                    dome_height=0.0, dome_rings=6):
        """
        Outer annulus joined to a central hub by radial spokes, with open gaps
        between them.

        `dome_height` raises the hub into a curved cap above `y1` rather than
        leaving it flat. `dome_rings` controls how smooth that curve is.
        """
        # Outer ring: circular cross-section, so it reads as a rounded band.
        self.use(rim_name)
        r_centre = (r_inner + r_outer) * 0.5
        r_tube = (r_outer - r_inner) * 0.5
        y_mid = (y0 + y1) * 0.5
        self.torus_band(r_centre, r_tube, y_mid, segs=segs, tube_segs=16)

        # Hub: a cylinder, optionally domed rather than flat on top.
        self.use(body_name)
        h_b = self.ring(hub_r, y0, segs)
        h_t = self.ring(hub_r, y1, segs)
        self.bridge(h_b, h_t, segs)
        self.cap(h_b, y0, segs, up=False)

        if dome_height <= 0.0:
            self.cap(h_t, y1, segs, up=True)
        else:
            # Quarter-ellipse profile from the hub edge up to the apex.
            prev = h_t
            for k in range(1, dome_rings + 1):
                t = k / dome_rings
                r = hub_r * math.cos(t * math.pi * 0.5)
                y = y1 + dome_height * math.sin(t * math.pi * 0.5)
                if k == dome_rings:
                    apex = self.v(0.0, y, 0.0)
                    for i in range(segs):
                        n = (i + 1) % segs
                        self.f(apex, prev[n], prev[i])
                else:
                    nxt = self.ring(r, y, segs)
                    self.bridge(prev, nxt, segs)
                    prev = nxt

        # Spokes: boxes spanning hub to ring, one per evenly spaced angle.
        half = spoke_width * 0.5
        for s in range(n_spokes):
            a = 2 * math.pi * s / n_spokes
            ca, sa = math.cos(a), math.sin(a)
            # Perpendicular offset, so the spoke has width across its length.
            px, pz = -sa * half, ca * half
            corners = []
            # Reach to the tube's centre line so the spoke sits inside the
            # torus rather than stopping at its inner edge.
            for r in (hub_r * 0.98, r_centre):
                for sign in (-1, 1):
                    x = r * ca + px * sign
                    z = r * sa + pz * sign
                    corners.append((x, z))
            # corners: [hub-, hub+, rim-, rim+]
            (hx0, hz0), (hx1, hz1), (rx0, rz0), (rx1, rz1) = corners
            b0 = self.v(hx0, y0, hz0); b1 = self.v(hx1, y0, hz1)
            b2 = self.v(rx1, y0, rz1); b3 = self.v(rx0, y0, rz0)
            t0 = self.v(hx0, y1, hz0); t1 = self.v(hx1, y1, hz1)
            t2 = self.v(rx1, y1, rz1); t3 = self.v(rx0, y1, rz0)
            self.f(t0, t1, t2, t3)          # top
            self.f(b3, b2, b1, b0)          # bottom
            self.f(b0, b1, t1, t0)          # hub end
            self.f(b2, b3, t3, t2)          # rim end
            self.f(b1, b2, t2, t1)          # side
            self.f(b3, b0, t0, t3)          # side

    # -- output --------------------------------------------------------------

    def save(self, path, name, materials, origin_at_base=True):
        verts = self.verts
        if origin_at_base and verts:
            # Drop the mesh so its lowest point sits at Y=0, putting the origin
            # at the contact tip rather than at the disc underside.
            lift = min(v[1] for v in verts)
            verts = [(x, y - lift, z) for x, y, z in verts]

        mtl_file = os.path.splitext(os.path.basename(path))[0] + ".mtl"
        with open(os.path.join(os.path.dirname(path), mtl_file), "w") as mf:
            mf.write(f"# {name} materials\n")
            for mat, (kd, ks, ns) in materials.items():
                mf.write(f"newmtl {mat}\n")
                mf.write(f"Kd {kd[0]:.3f} {kd[1]:.3f} {kd[2]:.3f}\n")
                mf.write(f"Ks {ks[0]:.3f} {ks[1]:.3f} {ks[2]:.3f}\n")
                mf.write(f"Ns {ns}\n\n")

        grouped = {}
        for face, mat in self.faces:
            grouped.setdefault(mat, []).append(face)

        with open(path, "w") as f:
            f.write(f"# {name} — Y-up, arena-scale units\n")
            f.write(f"mtllib {mtl_file}\n")
            f.write(f"o {name}\n")
            for x, y, z in verts:
                f.write(f"v {x:.6f} {y:.6f} {z:.6f}\n")
            for mat, faces in grouped.items():
                f.write(f"usemtl {mat}\n")
                for face in faces:
                    f.write("f " + " ".join(str(i) for i in face) + "\n")

        counts = {m: len(fs) for m, fs in grouped.items()}
        print(f"{name}: {len(self.verts)} verts, "
              f"{sum(counts.values())} faces, surfaces={counts}")


def spiked(r_base, length, n_spikes, width=0.16, tip_frac=0.35):
    """
    Returns a radius(angle) function: a circle of `r_base` with `n_spikes`
    protrusions of `length` sticking out of it.

    Unlike `bladed`, the rim between spikes stays exactly circular — the spikes
    are additions to a round disc rather than a continuous undulation.
    `width` is the angular half-width of a spike's base, as a fraction of the
    spacing between spikes. `tip_frac` sets how pointed it is: lower is sharper.
    """
    spacing = 2 * math.pi / n_spikes

    def r(a):
        # Angular distance to the nearest spike centre.
        off = (a % spacing) / spacing          # 0..1 between spikes
        d = min(off, 1.0 - off)                # 0 at a spike, 0.5 midway
        if d > width:
            return r_base
        t = d / width                          # 0 at centre, 1 at spike base
        if t < tip_frac:
            return r_base + length             # flat tip, so it reads as solid
        # Linear taper from the tip back down to the circle.
        return r_base + length * (1.0 - (t - tip_frac) / (1.0 - tip_frac))

    return r


def bladed(r_base, depth, n_blades, sharpness=0.30):
    """
    Returns a radius(angle) function producing `n_blades` protrusions.

    Rises quickly to the blade tip then falls away slowly, so each blade has a
    sharp leading edge and a swept trailing edge — the asymmetry reads as a
    direction of rotation.
    """
    def r(a):
        phase = (a * n_blades) % (2 * math.pi) / (2 * math.pi)
        if phase < sharpness:
            t = phase / sharpness
            return r_base + depth * t
        if phase < sharpness * 2.4:
            t = (phase - sharpness) / (sharpness * 1.4)
            return r_base + depth * (1.0 - t)
        return r_base
    return r


# ── ATTACK ────────────────────────────────────────────────────────────────────
# Nine wide blades, shallow disc, sharp shaft. Widest silhouette of the three.
m = OBJMesh()
blade = bladed(R * 0.80, R * 0.24, n_blades=9, sharpness=0.34)

m.use("Body")
m.shaft(r_top=R * 0.26, r_tip=R * 0.04, y_top=0.0, y_tip=-R * 0.62,
        segs=48, curve=0.40, rings=10)

m.banded_disc(
    profile=[
        (R * 0.62, 0.0),
        (blade,    R * 0.10),
        (blade,    R * 0.30),
        (R * 0.70, R * 0.40),
    ],
    segs=144, rim_name="Rim", body_name="Body", rim_frac=0.70,
    dome_height=R * 0.10, dome_rings=6,
)
m.save(
    os.path.join(OUTPUT, "top_attack.obj"), "Attack",
    {
        "Rim":  ((0.82, 0.82, 0.86), (0.90, 0.90, 0.90), 96),
        "Body": ((0.72, 0.14, 0.12), (0.30, 0.30, 0.30), 32),
    },
)

# ── STAMINA ───────────────────────────────────────────────────────────────────
# Circular disc with four evenly spaced spikes. Tall and narrow, needle tip.
m = OBJMesh()
spike = spiked(R * 0.72, R * 0.22, n_spikes=4, width=0.17, tip_frac=0.30)

m.use("Body")
m.shaft(r_top=R * 0.20, r_tip=R * 0.045, y_top=0.0, y_tip=-R * 0.60,
        segs=48, curve=0.55, rings=12)

m.banded_disc(
    profile=[
        (R * 0.62, 0.0),
        (spike,    R * 0.14),
        (spike,    R * 0.44),
        (R * 0.54, R * 0.60),
    ],
    segs=192, rim_name="Rim", body_name="Body", rim_frac=0.70,
    dome_height=R * 0.10, dome_rings=6,
)
m.save(
    os.path.join(OUTPUT, "top_stamina.obj"), "Stamina",
    {
        "Rim":  ((0.86, 0.86, 0.88), (0.92, 0.92, 0.92), 110),
        "Body": ((0.20, 0.58, 0.30), (0.28, 0.28, 0.28), 40),
    },
)

# ── DEFENCE ───────────────────────────────────────────────────────────────────
# Spoked ring: wide metallic band, five spokes, open gaps. Squat and heavy.
m = OBJMesh()

m.use("Body")
m.shaft(r_top=R * 0.30, r_tip=R * 0.075, y_top=0.0, y_tip=-R * 0.44,
        segs=48, curve=0.12, rings=10)

m.spoked_ring(
    r_inner=R * 0.66,
    r_outer=R * 1.00,
    hub_r=R * 0.52,
    y0=0.0,
    y1=R * 0.34,
    n_spokes=5,
    segs=120,
    rim_name="Rim",
    body_name="Body",
    spoke_width=R * 0.22,
    dome_height=R * 0.15,    # smaller bump than before
    dome_rings=7,
)
m.save(
    os.path.join(OUTPUT, "top_defence.obj"), "Defence",
    {
        "Rim":  ((0.80, 0.80, 0.84), (0.94, 0.94, 0.94), 120),
        "Body": ((0.16, 0.46, 0.72), (0.26, 0.26, 0.26), 36),
    },
)

print("\nDone. Radii: attack %.4f, stamina %.4f, defence %.4f"
      % (R * 1.04, R * 0.92, R * 1.00))
