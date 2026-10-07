"""Build the Face Cap mouth shape keys the Head is missing, as a first pass to sculpt on.

Run in your open fish file (Scripting workspace -> Open -> Run Script), or through the Blender MCP.
Only shape keys are written: no vertex is added, removed or reconnected, and the existing keys
(jawOpen, mouthClose, mouthFunnel, mouthPucker, mouthSmileLeft/Right) are never touched.
Re-running overwrites the keys this script made (same names), so tweak a number and run it again.
Once you sculpt on a key by hand, take it out of SHAPES below so a re-run doesn't overwrite it.

How it finds the mouth: the lips are closed edge rings around the mouth. Ring 0 is where the lips
meet (found from the jawOpen key: the lowest upper-lip vertex at the front), rings 1, 2, ... go
outward (1-2 the lips, 3-5 the skin around them), rings -1, -2 go inward (the lip lining); the
teeth (ring -4 and deeper) never move. Upper vs lower lip comes from how far jawOpen moves a
vertex. Left = the fish's own left (+X), like mouthSmileLeft.
"""
import math

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

HEAD = "Head"

# which keys to (re)build; drop a name once you've sculpted it by hand
SHAPES = [
    "mouthUpperUpLeft", "mouthUpperUpRight",
    "mouthLowerDownLeft", "mouthLowerDownRight",
    "mouthFrownLeft", "mouthFrownRight",
    "mouthStretchLeft", "mouthStretchRight",
    "mouthDimpleLeft", "mouthDimpleRight",
    "mouthPressLeft", "mouthPressRight",
    "mouthRollUpper", "mouthRollLower",
    "mouthShrugUpper", "mouthShrugLower",
    "mouthLeft", "mouthRight",
]
if "ONLY" in globals():   # run with ONLY = [...] predefined to build just those keys (also ones not in SHAPES)
    SHAPES = list(ONLY)

# sizes, in model units (the mouth is about 0.7 wide; mouthSmile moves its corner about 0.16)
UPPER_UP = 0.10        # upper lip lift
LOWER_DOWN = 0.10      # lower lip drop
FROWN = 0.10           # corner down
STRETCH = 0.07         # corner back and down (Face Cap sends ~0.3 even at rest, so keep it small)
DIMPLE = 0.055         # corner back into the cheek
PRESS = 0.05           # lips pushed back and thinned
ROLL = math.radians(38)  # lip rolled in about the line where the lips meet
SHRUG = 0.055          # lip pushed up and out
SIDE = math.radians(8)   # mouthLeft/Right: lips slide around the head
# mouthPucker (not built by default: run with ONLY = ["mouthPucker"]; it would replace a hand-sculpted one)
PUCKER_SQUEEZE = 0.8   # how much narrower the lips get (0.8 = to about a third of their width; corners bunch up)
PUCKER_FORWARD = 0.16  # how far the bunched lips push out
PUCKER_FULL = 0.9      # how far squeezed lip material comes forward to the front of the mouth (0..1)

# how much each ring moves (ring 0 = where the lips meet; negative = inside the mouth)
LIP = {-3: 0.3, -2: 0.7, -1: 1, 0: 1, 1: 1, 2: 1, 3: 0.8, 4: 0.55, 5: 0.3, 6: 0.12, 7: 0.03}


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


head = bpy.data.objects[HEAD]
me = head.data
kb = me.shape_keys.key_blocks
n = len(me.vertices)


def key_co(name):
    a = np.empty(n * 3)
    kb[name].data.foreach_get("co", a)
    return a.reshape(-1, 3)


B = key_co(kb[0].name)
jaw = np.linalg.norm(key_co("jawOpen") - B, axis=1)

bm = bmesh.new()
bm.from_mesh(me)
bm.verts.ensure_lookup_table()
nb = [[e.other_vert(v).index for e in v.link_edges] for v in bm.verts]

# ---- ring 0: the edge loop through the lowest upper-lip vertex at the front, on the middle line
front = B[:, 1].min()
seed = min((i for i in range(n) if abs(B[i, 0]) < 1e-4 and B[i, 1] < front + 0.12 and jaw[i] < 0.02),
           key=lambda i: B[i, 2])


def edge_loop(vi):
    v = bm.verts[vi]
    e = max(v.link_edges, key=lambda e: (e.other_vert(v).co.x - v.co.x) - 0.5 * abs(e.other_vert(v).co.z - v.co.z))
    loop = [vi]
    while True:
        w = e.other_vert(v)
        if w.index == vi:
            return loop
        loop.append(w.index)
        if len(w.link_edges) != 4 or len(loop) > 200:
            raise RuntimeError(f"ring 0 is not a clean quad loop (stopped at vertex {w.index})")
        faces = set(e.link_faces)
        v, e = w, next(x for x in w.link_edges if x is not e and not (set(x.link_faces) & faces))


ring = {i: 0 for i in edge_loop(seed)}
# the two rings next to it: the one reaching furthest forward is ring 1 (outside), the other ring -1
around = {j for i in ring for j in nb[i] if j not in ring}
parts = []
while around:
    stack = [around.pop()]
    part = set(stack)
    while stack:
        i = stack.pop()
        for j in nb[i]:
            if j in around:
                around.discard(j)
                part.add(j)
                stack.append(j)
    parts.append(part)
if len(parts) != 2:
    raise RuntimeError(f"expected two rings next to ring 0, found {len(parts)}")
outer = min(parts, key=lambda p: B[list(p), 1].min())
inner = parts[1] if outer is parts[0] else parts[0]
for sign, first in ((1, outer), (-1, inner)):
    for i in first:
        ring[i] = sign
    cur, k = first, 1
    while cur and k < 14:
        k += 1
        cur = {j for i in cur for j in nb[i] if j not in ring}
        for j in cur:
            ring[j] = sign * k

R = np.array([ring.get(i, 99) for i in range(n)])
lip_w = np.array([LIP.get(int(r), 0.0) for r in R])           # outward falloff, teeth 0
teeth_w = np.where(R >= -1, 1.0, np.where(R == -2, 0.7, np.where(R == -3, 0.3, 0.0)))
teeth_w[R == 99] = 0.0
lower = smoothstep(0.08, 0.38, jaw)                             # 1 = moves with the lower jaw
upper = 1 - lower
X, Y, Z = B[:, 0], B[:, 1], B[:, 2]
r0 = [i for i in ring if ring[i] == 0]
corner = {s: B[sorted(r0, key=lambda i: -s * B[i, 0])[:2]].mean(axis=0) for s in (1, -1)}

# pivot for the rolls: for every vertex, the ring-0 point on its own side (upper/lower) nearest in x
r0_up = sorted([i for i in r0 if lower[i] < 0.5], key=lambda i: B[i, 0])
r0_lo = sorted([i for i in r0 if lower[i] >= 0.5], key=lambda i: B[i, 0])


def ring0_point(xq, idx):
    xs = B[idx, 0]
    xq = float(np.clip(xq, xs.min(), xs.max()))
    j = int(np.clip(np.searchsorted(xs, xq), 1, len(idx) - 1))
    a, b = B[idx[j - 1]], B[idx[j]]
    t = (xq - a[0]) / max(1e-6, b[0] - a[0])
    return a + (b - a) * t


def ring0_frame(xq, idx, h=0.04):
    """Point on ring 0 at x = xq and the ring's direction there (looking both ways, so both sides match)."""
    tangent = Vector(ring0_point(xq + h, idx) - ring0_point(xq - h, idx)).normalized()
    return Vector(ring0_point(xq, idx)), tangent


# vertex normals at rest: skin slides along the surface by dropping the part of a move along its normal
bm.normal_update()
normals = np.array([v.normal[:] for v in bm.verts])
bm.free()


def slide(D, amount):
    """Keep skin on the head: from ring 3 outward, moves lose their component along the surface normal."""
    s = smoothstep(2.5, 4.0, R.astype(float)) * amount
    s[R == 99] = 0
    along = (D * normals).sum(axis=1)
    return D - normals * (along * s)[:, None]


def side_w(s, a=-0.22, b=0.22):
    return smoothstep(a, b, s * X)


def corner_w(s, sigma):
    d2 = ((B - corner[s]) ** 2).sum(axis=1)
    return np.exp(-d2 / (sigma * sigma)) * teeth_w


mid_w = 1 - 0.55 * smoothstep(0.18, 0.38, np.abs(X))          # lips lift less at the corners


def shape(name):
    D = np.zeros_like(B)
    s = -1 if name.endswith("Right") else 1
    if name.startswith("mouthUpperUp"):
        w = UPPER_UP * upper * lip_w * side_w(s) * mid_w
        D[:, 2] = w
        D[:, 1] = 0.2 * w
    elif name.startswith("mouthLowerDown"):
        w = LOWER_DOWN * lower * lip_w * side_w(s) * mid_w
        D[:, 2] = -w
        D[:, 1] = -0.2 * w
    elif name.startswith("mouthFrown"):
        w = corner_w(s, 0.24)
        D += np.outer(w, [s * 0.15, 0.1, -1.0]) * FROWN
        D = slide(D, 0.8)
    elif name.startswith("mouthStretch"):
        # mostly back and down, hardly wider: smile and dimple already widen the corners, and
        # Face Cap adds stretch to almost every smile, so a wide stretch would double up
        w = corner_w(s, 0.28)
        D += np.outer(w, np.array([s * 0.25, 0.55, -0.8])) * STRETCH
        band = np.array([{1: 1, 2: 1, 3: 0.6, 4: 0.3}.get(int(r), 0.0) for r in R]) * side_w(s, -0.3, 0.3)
        D[:, 1] += 0.4 * PRESS * band                                  # lips flatten...
        D[:, 2] += 0.3 * PRESS * band * (lower - upper)                # ...and thin a little
        D = slide(D, 0.9)
    elif name.startswith("mouthDimple"):
        w = corner_w(s, 0.2)
        D += np.outer(w, [s * 0.12, 0.95, 0.12]) * DIMPLE              # back into the cheek, not wider
        D = slide(D, 1.0)
    elif name.startswith("mouthPress"):
        band = np.array([{1: 1, 2: 1, 3: 0.6, 4: 0.3, 5: 0.1}.get(int(r), 0.0) for r in R]) * side_w(s, -0.3, 0.3)
        D[:, 1] = PRESS * band
        D[:, 2] = PRESS * 0.6 * band * (lower - upper)               # upper lip down, lower lip up
    elif name in ("mouthRollUpper", "mouthRollLower"):
        up = name == "mouthRollUpper"
        part = upper if up else lower
        idx = r0_up if up else r0_lo
        roll = {0: 1, 1: 1, 2: 1, 3: 0.6, 4: 0.3, 5: 0.1}
        fade = 1 - smoothstep(0.16, 0.34, np.abs(X))
        for i in range(n):
            w = roll.get(int(R[i]), 0.0) * part[i] * fade[i]
            if w <= 0:
                continue
            pivot, t = ring0_frame(X[i], idx)
            if t.x < 0:
                t = -t
            # upper lip: its front turns back and up into the mouth; lower lip: back and down
            m = Matrix.Rotation((-ROLL if up else ROLL) * w, 3, t)
            p = Vector(B[i])
            D[i] = np.array(m @ (p - pivot) + pivot - p)
    elif name == "mouthShrugUpper":
        w = SHRUG * upper * lip_w * mid_w * (R >= 0)
        D[:, 2] = w * np.where(R >= 2, 1.0, np.where(R == 1, 0.6, 0.3))   # the lip line rises least
        D[:, 1] = -0.7 * w
    elif name == "mouthShrugLower":
        band = np.array([{0: 0.2, 1: 1, 2: 1, 3: 1, 4: 0.9, 5: 0.6, 6: 0.3, 7: 0.1}.get(int(r), 0.0) for r in R])
        w = SHRUG * lower * band * mid_w
        D[:, 1] = -1.1 * w                                             # pout forward
        D[:, 2] = 0.7 * w * (R >= 1)                                   # chin pushes it up; the lip line stays
    elif name == "mouthPucker":
        # a drawstring around the lips: in cylinder coordinates about a vertical axis through the
        # head, every lip vertex's angle shrinks toward the middle and its radius grows (the
        # squeezed corners come forward to the front, then everything pushes out)
        # the lining inside the lips squeezes as much as the lips (else it pokes out at the corners)
        q_ring = {-3: 0.6, -2: 1, -1: 1, 0: 1, 1: 1, 2: 1, 3: 0.8, 4: 0.55, 5: 0.32, 6: 0.15, 7: 0.05}
        fwd_ring = {-3: 0.3, -2: 0.6, -1: 0.85, 0: 1, 1: 1, 2: 1, 3: 0.75, 4: 0.5, 5: 0.28, 6: 0.12, 7: 0.03}
        thick_ring = {2: 0.5, 3: 1, 4: 0.7, 5: 0.3, 6: 0.1}   # lips grow from their outer edge; the lip line stays shut
        centre = np.array([0.0, -0.1])
        rel = B[:, :2] - centre
        rho = np.hypot(rel[:, 0], -rel[:, 1])
        theta = np.arctan2(rel[:, 0], -rel[:, 1])
        front = {}
        for r in set(int(x) for x in R if abs(x) <= 7):
            ids = np.nonzero(R == r)[0]
            front[r] = rho[ids].max()                     # the ring's front, on the middle line
        for i in range(n):
            r = int(R[i])
            q = q_ring.get(r, 0.0)
            if q <= 0:
                continue
            th = theta[i] * (1 - PUCKER_SQUEEZE * q)
            rh = rho[i] + (front[r] - rho[i]) * PUCKER_FULL * q * min(1.0, abs(theta[i]) / 0.35)
            rh += PUCKER_FORWARD * fwd_ring.get(r, 0.0) * teeth_w[i]
            x, y = math.sin(th) * rh, -math.cos(th) * rh
            D[i, 0] = x + centre[0] - B[i, 0]
            D[i, 1] = y + centre[1] - B[i, 1]
                # the squeeze makes the lips taller: upper lip up, lower lip down (the lip line stays)
            D[i, 2] = 0.05 * PUCKER_SQUEEZE * thick_ring.get(r, 0.0) * (upper[i] - lower[i])
    elif name in ("mouthLeft", "mouthRight"):
        a = SIDE if name == "mouthLeft" else -SIDE
        w = lip_w * teeth_w
        centre = np.array([0.0, -0.1, 0.0])
        for i in np.nonzero(w > 0)[0]:
            m = Matrix.Rotation(a * w[i], 3, "Z")
            p = Vector(B[i] - centre)
            D[i] = np.array(m @ p - p)
    else:
        raise KeyError(name)
    return D


made = []
for name in SHAPES:
    D = shape(name)
    key = kb.get(name)
    if key is None:
        key = head.shape_key_add(name=name, from_mix=False)
        key.value = 0.0
    key.relative_key = kb[0]
    key.slider_min, key.slider_max = 0.0, 1.0
    key.data.foreach_set("co", (B + D).ravel())
    made.append((name, round(float(np.linalg.norm(D, axis=1).max()), 3)))
me.update()
print("MOUTH SHAPES", made)
result = {"made": made, "ring0_seed": int(seed), "rings": {int(r): int((R == r).sum()) for r in range(-4, 8)}}
