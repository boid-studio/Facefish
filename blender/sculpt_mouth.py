"""Narrower mouth with rounder lips, towards the artist's expression sheets.

    /Applications/Blender.app/Contents/MacOS/Blender -b blender/fish_starter10.blend -P blender/sculpt_mouth.py

The mouth corners (and the mouth inside them) move towards the middle and slightly up into a smile;
then the lip region is relaxed so the flat upper-lip shelf rounds into a roll. Every shape key layer
gets the same offsets; re-run make_face_shapes.py afterwards.
"""
import math

import bmesh
import bpy
from mathutils import Vector

NARROW = 0.16          # how far each corner moves in (the mouth was ~75% of the head's width)
CORNER_LIFT = 0.03
RELAX_ITER = 6
BALL_X, BALL_Z = 0.86, 0.90   # the head's ball (sculpt_round.py): corners follow its curve forward


def ball_z(x):
    return BALL_Z * math.sqrt(max(0.0, 1 - (x / BALL_X) ** 2))

head = bpy.data.objects["Head"]
me = head.data
kb = me.shape_keys.key_blocks
for k in kb:
    k.value = 0.0


def smooth(a, b, x):
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


bm = bmesh.new()
bm.from_mesh(me)
layers = [bm.verts.layers.shape[k.name] for k in kb]
B = bm.verts.layers.shape["Basis"]
partl = bm.faces.layers.float.get("part")
kinds = {v: {int(round(f[partl])) for f in v.link_faces} for v in bm.verts}
edge = [v for v in bm.verts if 0 in kinds[v] and len(kinds[v]) > 1]
cornerL = max((v[B] for v in edge), key=lambda p: p.x).copy()
cornerR = min((v[B] for v in edge), key=lambda p: p.x).copy()


def move(v, d):
    for layer in layers:
        v[layer] = v[layer] + d
    v.co = v[B]


moves = {}
for v in bm.verts:
    if 2 in kinds[v]:
        continue                                  # teeth stay where they are
    p = v[B]
    d = Vector()
    for c, sign in ((cornerL, 1), (cornerR, -1)):
        w = 1 - smooth(0.05, 0.45, (p - c).length)
        if w > 0 and p.x * sign > -0.05:
            dx = -sign * NARROW * w
            dz = ball_z(p.x + dx) - ball_z(p.x)
            d += Vector((dx, CORNER_LIFT * w, dz))
    if d.length > 0:
        moves[v] = d
for v, d in moves.items():
    move(v, d)

# round the lips: relax the outer lip skin near the mouth line
edge_pts = [v[B].copy() for v in edge]
lip = [v for v in bm.verts if 0 in kinds[v] and min((v[B] - q).length for q in edge_pts) < 0.2 and v not in edge]
for _ in range(RELAX_ITER):
    upd = {}
    for v in lip:
        nb = [e.other_vert(v)[B] for e in v.link_edges]
        target = sum(nb, Vector()) / len(nb)
        d = target - v[B]
        # keep the volume: relax along the surface only, then push back out a little
        n = v.normal
        d -= n * d.dot(n) * 0.7
        upd[v] = d * 0.4
    for v, d in upd.items():
        move(v, d)
bm.to_mesh(me)
bm.free()
me.update()
bpy.ops.wm.save_mainfile()
print("MOUTH", {"corner_moved": len(moves), "relaxed": len(lip),
                "corners": [[round(x, 2) for x in cornerL], [round(x, 2) for x in cornerR]]})
