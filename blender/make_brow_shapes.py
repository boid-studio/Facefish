"""Build the Face Cap brow and cheek shape keys on the Head, as a first pass to sculpt on, plus an empty tongueOut.

Run in your open fish file (Scripting workspace -> Open -> Run Script), or through the Blender MCP.
Only shape keys are written; no vertex is added, removed or reconnected, and other keys are untouched.
Re-running only creates brow keys that are missing, so sculpted ones are safe; set REBUILD = True (or
run with ONLY = [...]) to rebuild existing ones. To make one side from the other, use mirror_keys.py. tongueOut is only created when it doesn't exist, and never overwritten.

How it works: each brow turns about its eyeball's centre (like the lids do), so it slides over the
eye instead of pushing into it. Around each eye socket (the hole in the head) the script counts edge
rings outward and measures each vertex's angle around the eye: 0 = outer corner, 90 = top,
180 = inner corner. browDown turns the top of the ring down (and draws the inner brow in a little),
browOuterUp lifts the outer part, browInnerUp the inner part and the middle of the forehead.
Left = the fish's own left (+X), like mouthSmileLeft.
"""
import math

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

HEAD = "Head"
EYES = {1: "Eye.L", -1: "Eye.R"}
SHAPES = ["browDownLeft", "browDownRight", "browInnerUp", "browOuterUpLeft", "browOuterUpRight",
          "cheekSquintLeft", "cheekSquintRight", "cheekPuff"]
REBUILD = False   # False: only create brow keys that are missing, so hand-sculpted ones are never overwritten
if "ONLY" in globals():   # run with ONLY = [...] predefined to (re)build exactly those keys
    SHAPES = list(ONLY)
    REBUILD = True

BROW_DOWN = math.radians(24)      # how far a brow turns down
BROW_IN = 0.04                    # browDown also draws the inner brow toward the middle
BROW_OUTER_UP = math.radians(28)
BROW_INNER_UP = math.radians(28)
RING = {0: 1, 1: 1, 2: 0.85, 3: 0.6, 4: 0.35, 5: 0.15, 6: 0.05}   # falloff from the socket outward
REACH = (0.34, 0.55)              # and from the eye's centre: full inside, nothing beyond
CHEEK_SQUINT = math.radians(14)   # the cheek under the eye rolls up around the eyeball...
CHEEK_SWELL = 0.025               # ...and bulges out a little
CHEEK_PUFF = 0.3                  # toony puff: how far the cheeks blow out (at the fullest point)
PUFF_CHEEKS = [(0.5, -0.66, -0.47), (-0.5, -0.66, -0.47)]   # where each cheek swells most
PUFF_JOWL = (0.0, -0.85, -0.75)   # a softer swell under the mouth, for roundness


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


head = bpy.data.objects[HEAD]
me = head.data
if me.shape_keys is None:
    head.shape_key_add(name="Basis", from_mix=False)
kb = me.shape_keys.key_blocks
n = len(me.vertices)
B = np.empty(n * 3)
kb[0].data.foreach_get("co", B)
B = B.reshape(-1, 3)
X = B[:, 0]

bm = bmesh.new()
bm.from_mesh(me)
bm.verts.ensure_lookup_table()
nb = [[e.other_vert(v).index for e in v.link_edges] for v in bm.verts]
boundary = {v.index for e in bm.edges if e.is_boundary for v in e.verts}
bm.normal_update()
normals = np.array([v.normal[:] for v in bm.verts])
bm.free()

to_head = head.matrix_world.inverted()
eye = {}
for s, name in EYES.items():
    c = np.array(to_head @ bpy.data.objects[name].matrix_world.translation)
    # the socket: the boundary vertices around this eye, then edge rings outward from it
    socket = {i for i in boundary if np.linalg.norm(B[i] - c) < 0.35}
    if not socket:
        raise RuntimeError(f"no eye socket (open edge loop) found around {name}")
    ring = {i: 0 for i in socket}
    cur, k = socket, 0
    while cur and k < max(RING):
        k += 1
        cur = {j for i in cur for j in nb[i] if j not in ring}
        for j in cur:
            ring[j] = k
    R = np.array([ring.get(i, 99) for i in range(n)])
    u = s * (X - c[0])                                   # + = toward the outer corner
    theta = np.degrees(np.arctan2(B[:, 2] - c[2], u))    # 0 outer, 90 top, 180 inner
    dist = np.linalg.norm(B - c, axis=1)
    w = np.array([RING.get(int(r), 0.0) for r in R]) * (1 - smoothstep(*REACH, dist))
    w *= smoothstep(-0.12, 0.12, s * X)                  # each side owns its half; the middle is shared
    eye[s] = {"c": c, "theta": theta, "w": w}


def turn(D, s, angle_per_vertex):
    """Turn vertices about the eye's sideways axis through its centre (+ = down over the eye)."""
    c = Vector(eye[s]["c"])
    for i in np.nonzero(np.abs(angle_per_vertex) > 1e-6)[0]:
        p = Vector(B[i])
        q = Matrix.Rotation(float(angle_per_vertex[i]), 3, "X") @ (p - c) + c
        D[i] += np.array(q - p)


def shape(name):
    D = np.zeros_like(B)
    sides = [-1] if name.endswith("Right") else [1] if name.endswith("Left") else [1, -1]
    for s in sides:
        e = eye[s]
        th = e["theta"]
        if name.startswith("browDown"):
            top = smoothstep(5, 40, th) * (1 - smoothstep(165, 195, th))
            turn(D, s, BROW_DOWN * e["w"] * top)
            D[:, 0] += -s * BROW_IN * e["w"] * smoothstep(90, 150, th) * top
        elif name.startswith("browOuterUp"):
            outer = smoothstep(-10, 20, th) * (1 - smoothstep(85, 130, th))
            turn(D, s, -BROW_OUTER_UP * e["w"] * outer)
        elif name.startswith("cheekSquint"):
            # below and outside the eye (-90 = straight down, -10 = outer corner); not the mouth
            below = smoothstep(-175, -125, th) * (1 - smoothstep(-25, 5, th))
            w = e["w"] * below * smoothstep(-0.42, -0.25, B[:, 2])
            turn(D, s, -CHEEK_SQUINT * w)                           # up around the eye, like a lower lid
            out = B - e["c"]
            D += out / np.maximum(np.linalg.norm(out, axis=1), 1e-6)[:, None] * (CHEEK_SWELL * w)[:, None]
        elif name == "cheekPuff":
            if s == -1:
                continue                                            # both cheeks are done in one go
            centre = np.array([0.0, -0.2, -0.3])                    # roughly the middle of the head
            radial = B - centre
            radial /= np.linalg.norm(radial, axis=1)[:, None]
            outward = smoothstep(0.15, 0.45, (normals * radial).sum(axis=1))   # outer skin only, not inside the mouth
            g = sum(np.exp(-((B - np.array(c)) ** 2).sum(axis=1) / 0.4 ** 2) for c in PUFF_CHEEKS)
            g = g + 0.55 * np.exp(-((B - np.array(PUFF_JOWL)) ** 2).sum(axis=1) / 0.3 ** 2)
            g *= 1 - smoothstep(-0.2, 0.05, B[:, 2])                 # nothing at the eyes and above
            amount = np.minimum(g, 1.0) * outward
            D += normals * amount[:, None]
            for _ in range(4):                                      # round it off: relax the puff a little
                D = 0.5 * D + 0.5 * np.array([D[nb[i]].mean(axis=0) if nb[i] else D[i] for i in range(n)])
            D *= CHEEK_PUFF / max(1e-6, np.linalg.norm(D, axis=1).max())   # the relaxing mustn't shrink it
            lips = np.exp(-((B - np.array([0.0, -1.05, -0.45])) ** 2).sum(axis=1) / 0.18 ** 2) * outward
            D[:, 1] -= 0.04 * lips                                  # closed lips pushed out by the air
        elif name == "browInnerUp":
            inner = smoothstep(70, 120, th) * (1 - smoothstep(185, 215, np.where(th < 0, th + 360, th)))
            turn(D, s, -BROW_INNER_UP * e["w"] * inner)
        else:
            raise KeyError(name)
    return D


made = []
for name in SHAPES:
    if name in kb and not REBUILD:
        continue
    D = shape(name)
    key = kb.get(name)
    if key is None:
        key = head.shape_key_add(name=name, from_mix=False)
        key.value = 0.0
    key.relative_key = kb[0]
    key.slider_min, key.slider_max = 0.0, 1.0
    key.data.foreach_set("co", (B + D).ravel())
    made.append((name, round(float(np.linalg.norm(D, axis=1).max()), 3)))

if "tongueOut" not in kb:                 # empty, to sculpt the tongue poking out
    key = head.shape_key_add(name="tongueOut", from_mix=False)
    key.value = 0.0
    key.relative_key = kb[0]
    made.append(("tongueOut", 0.0))
me.update()
print("BROW SHAPES", made)
result = {"made": made}
