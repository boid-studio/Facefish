"""Sculpt pass towards the artist's expression sheets: rounder fish, smaller eyes, fuller lips.

    /Applications/Blender.app/Contents/MacOS/Blender -b blender/fish_starter10.blend -P blender/sculpt_round.py

1. eyes: scale each eyeball and its socket about the eye centre (EYE_SCALE)
2. ball: every outside vertex moves towards one egg-shaped ball (front and back radii differ),
   protected around the eyes, lips and mouth so the face keeps its features and the lips end up
   protruding from the ball like the reference's snout; the tail stalk is left alone
3. lips: pushed forward and thickened away from the mouth line
Every shape key gets the same offsets, so the face shapes keep working (re-run
make_face_shapes.py afterwards to rebuild them on the new shape).
Head-local coordinates: +x fish's left, +y up, +z front.
"""
import math

import bmesh
import bpy
from mathutils import Vector

EYE_SCALE = 0.84
CENTER = Vector((0.0, -0.42, 0.0))
RADII_FRONT = Vector((0.86, 0.97, 0.90))    # x, y, z for z >= centre
RADII_BACK = Vector((0.86, 0.97, 0.86))     # z < centre
BALL_STRENGTH = 0.9
LIP_FORWARD = 0.06
LIP_THICKEN = 0.035

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
partl = bm.faces.layers.float.get("part")


def move(v, d):
    for layer in layers:
        v[layer] = v[layer] + d
    v.co = v[B]


# ---- 1. eyes
eyes = [(Minv @ e.matrix_world.translation, max(e.dimensions) / 2) for e in eye_objs]
for v in bm.verts:
    p = v[B]
    tot, ws = Vector(), 0.0
    for c, r in eyes:
        w = 1 - smooth(r + 0.10, r + 0.34, (p - c).length)
        if w > 0:
            tot += (p - c) * (EYE_SCALE - 1) * w
            ws += w
    if ws > 0:
        move(v, tot / max(1.0, ws))
for e in eye_objs:
    e.scale = e.scale * EYE_SCALE
eyes = [(c, r * EYE_SCALE) for c, r in eyes]

# ---- regions
kinds = {v: {int(round(f[partl])) for f in v.link_faces} for v in bm.verts}
exterior = {v for v in bm.verts if 0 in kinds[v]}
edge_pts = [v[B].copy() for v in bm.verts if 0 in kinds[v] and len(kinds[v]) > 1]


def lipdist(p):
    return min((p - q).length for q in edge_pts)


def ball_point(p):
    d = p - CENTER
    R = RADII_FRONT if d.z >= 0 else RADII_BACK
    s = math.sqrt((d.x / R.x) ** 2 + (d.y / R.y) ** 2 + (d.z / R.z) ** 2)
    return CENTER + d / max(s, 1e-6), s


# ---- 2. ball
stalk_z = CENTER.z - RADII_BACK.z * 0.82
moves = {}
for v in exterior:
    p = v[B]
    protect = 0.0
    for c, r in eyes:
        protect = max(protect, 1 - smooth(r + 0.06, r + 0.3, (p - c).length))
    protect = max(protect, 1 - smooth(0.12, 0.34, lipdist(p)))
    w = BALL_STRENGTH * (1 - protect) * (1 - smooth(stalk_z, stalk_z - 0.12, p.z))
    if w <= 1e-4:
        continue
    target, _ = ball_point(p)
    moves[v] = (target - p) * w
for v, d in moves.items():
    move(v, d)
# relax the reshaped skin a little so the old creases soften
reshaped = [v for v in moves if moves[v].length > 1e-3]
for _ in range(3):
    upd = {}
    for v in reshaped:
        nb = [e.other_vert(v)[B] for e in v.link_edges]
        upd[v] = (sum(nb, Vector()) / len(nb) - v[B]) * 0.25 * min(1.0, moves[v].length * 8)
    for v, d in upd.items():
        move(v, d)

# ---- 3. lips: forward and fuller, away from the mouth line (mouth interior follows the lips)
lip_moves = {}
for v in bm.verts:
    p = v[B]
    ld = lipdist(p)
    w = 1 - smooth(0.02, 0.24, ld)
    if w <= 0 or 2 in kinds[v]:
        continue
    near = min(edge_pts, key=lambda q: (p - q).length)
    away = p - near
    away.z = 0.0
    away = away.normalized() if away.length > 1e-5 else Vector()
    d = Vector((0, 0, LIP_FORWARD * w)) + away * LIP_THICKEN * w * (1.0 if v in exterior else 0.4)
    lip_moves[v] = d
for v, d in lip_moves.items():
    move(v, d)

bmesh.ops.recalc_face_normals(bm, faces=[f for f in bm.faces])
bm.to_mesh(me)
bm.free()
me.update()
bpy.ops.wm.save_mainfile()
print("SCULPT", {"eye_scale": EYE_SCALE, "ball_moved": len(moves), "lip_moved": len(lip_moves)})
