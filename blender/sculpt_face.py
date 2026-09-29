"""Second sculpt pass on the face, towards the artist's expression sheets.

    /Applications/Blender.app/Contents/MacOS/Blender -b blender/fish_starter10.blend -P blender/sculpt_face.py

1. eyes further round the sides of the ball: each socket region turns about the ball's vertical
   axis (EYE_SPREAD_DEG); the eyeballs move with it but keep looking straight ahead
2. a closed mouth at rest: the lower lip comes up and the upper lip down onto the mouth line, so
   the neutral face is the reference's closed smile and jawOpen opens it from there
3. fuller lips, pushed a little further forward
Every shape key layer gets the same offsets. Head-local coordinates: +x left, +y up, +z front.
"""
import math

import bmesh
import bpy
from mathutils import Matrix, Vector

EYE_SPREAD_DEG = 11.0
CENTER = Vector((0.0, -0.42, 0.0))
CLOSE_LOWER = 0.055
CLOSE_UPPER = 0.02
LIP_FULL = 0.03
LIP_FORWARD = 0.025

head = bpy.data.objects["Head"]
me = head.data
kb = me.shape_keys.key_blocks
for k in kb:
    k.value = 0.0
Minv = head.matrix_world.inverted()
eye_objs = [bpy.data.objects["Eye.L"], bpy.data.objects["Eye.R"]]


def smooth(a, b, x):
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


bm = bmesh.new()
bm.from_mesh(me)
layers = [bm.verts.layers.shape[k.name] for k in kb]
B = bm.verts.layers.shape["Basis"]
J = bm.verts.layers.shape["jawOpen"]
partl = bm.faces.layers.float.get("part")


def move(v, d):
    for layer in layers:
        v[layer] = v[layer] + d
    v.co = v[B]


# ---- 1. spread the eyes
eyes = [(Minv @ e.matrix_world.translation, max(e.dimensions) / 2, 1 if e.name.endswith(".L") else -1) for e in eye_objs]
for v in bm.verts:
    p = v[B]
    total = Vector()
    for c, r, side in eyes:
        w = 1 - smooth(r + 0.14, r + 0.42, (p - c).length)
        if w <= 0 or p.x * side < -0.02:
            continue
        rot = Matrix.Rotation(math.radians(EYE_SPREAD_DEG * side * w), 3, "Y")
        total += (CENTER + rot @ (p - CENTER)) - p
    if total.length > 0:
        move(v, total)
for e, (c, r, side) in zip(eye_objs, eyes):
    rot = Matrix.Rotation(math.radians(EYE_SPREAD_DEG * side), 3, "Y")
    new_local = CENTER + rot @ (c - CENTER)
    e.matrix_world.translation = head.matrix_world @ new_local

# ---- regions around the mouth
kinds = {v: {int(round(f[partl])) for f in v.link_faces} for v in bm.verts}
edge = [v for v in bm.verts if 0 in kinds[v] and len(kinds[v]) > 1]
edge_pts = [v[B].copy() for v in edge]
jd = {v: (v[J] - v[B]) for v in bm.verts}
jmax = max(d.length for d in jd.values())


def lipdist(p):
    return min((p - q).length for q in edge_pts)


# ---- 2. close the mouth at rest
close = {}
for v in bm.verts:
    if 2 in kinds[v] or 3 in kinds[v]:
        continue                                   # teeth and tongue stay
    p = v[B]
    w = 1 - smooth(0.0, 0.2, lipdist(p))
    if w <= 0:
        continue
    lower = jd[v].y < -0.01 and jd[v].length / jmax > 0.08
    close[v] = Vector((0, CLOSE_LOWER * w if lower else -CLOSE_UPPER * w, 0))
for v, d in close.items():
    move(v, d)

# ---- 3. fuller lips
full = {}
edge_pts = [v[B].copy() for v in edge]
for v in bm.verts:
    if 2 in kinds[v] or 3 in kinds[v]:
        continue
    p = v[B]
    ld = lipdist(p)
    w = 1 - smooth(0.02, 0.22, ld)
    if w <= 0:
        continue
    near = min(edge_pts, key=lambda q: (p - q).length)
    away = p - near
    away.z = 0.0
    away = away.normalized() if away.length > 1e-5 else Vector()
    full[v] = Vector((0, 0, LIP_FORWARD * w)) + away * LIP_FULL * w * (1.0 if 0 in kinds[v] else 0.3)
for v, d in full.items():
    move(v, d)

bm.to_mesh(me)
bm.free()
me.update()
bpy.ops.wm.save_mainfile()
print("FACE", {"spread_deg": EYE_SPREAD_DEG, "closed": len(close), "fuller": len(full),
               "eyes": [[round(x, 2) for x in e.matrix_world.translation] for e in eye_objs]})
