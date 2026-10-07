"""Build the Face Cap brow shape keys on the Head, as a first pass to sculpt on, plus an empty tongueOut.

Run in your open fish file (Scripting workspace -> Open -> Run Script), or through the Blender MCP.
Only shape keys are written; no vertex is added, removed or reconnected, and other keys are untouched.
Re-running overwrites the keys this script made (same names); take a key out of SHAPES once you've
sculpted it by hand. tongueOut is only created when it doesn't exist, and never overwritten.

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
SHAPES = ["browDownLeft", "browDownRight", "browInnerUp", "browOuterUpLeft", "browOuterUpRight"]
if "ONLY" in globals():   # run with ONLY = [...] predefined to build just those keys
    SHAPES = list(ONLY)

BROW_DOWN = math.radians(24)      # how far a brow turns down
BROW_IN = 0.04                    # browDown also draws the inner brow toward the middle
BROW_OUTER_UP = math.radians(28)
BROW_INNER_UP = math.radians(28)
RING = {0: 1, 1: 1, 2: 0.85, 3: 0.6, 4: 0.35, 5: 0.15, 6: 0.05}   # falloff from the socket outward
REACH = (0.34, 0.55)              # and from the eye's centre: full inside, nothing beyond


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
bm.free()

to_head = head.matrix_world.inverted()
eye = {}
for s, name in EYES.items():
    c = np.array(to_head @ bpy.data.objects[name].matrix_world.translation)
    # the socket: the boundary vertices around this eye, then edge rings outward from it
    socket = {i for i in boundary if np.linalg.norm(B[i] - c) < 0.35}
    if not socket:
        raise SystemExit(f"no eye socket (open edge loop) found around {name}")
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
        elif name == "browInnerUp":
            inner = smoothstep(70, 120, th) * (1 - smoothstep(185, 215, np.where(th < 0, th + 360, th)))
            turn(D, s, -BROW_INNER_UP * e["w"] * inner)
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

if "tongueOut" not in kb:                 # empty, to sculpt the tongue poking out
    key = head.shape_key_add(name="tongueOut", from_mix=False)
    key.value = 0.0
    key.relative_key = kb[0]
    made.append(("tongueOut", 0.0))
me.update()
print("BROW SHAPES", made)
result = {"made": made}
