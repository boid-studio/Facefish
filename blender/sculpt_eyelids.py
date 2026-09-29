"""Lidded eyes at rest, like the artist's references, so blinks can close over the bulging eyeballs.

    /Applications/Blender.app/Contents/MacOS/Blender -b blender/fish_starter10.blend -P blender/sculpt_eyelids.py

The Head is open behind each eyeball; the rim of that hole is the lid edge and the edge loops around
it are the lids (see lidlib.py). This pass works on the Head's own vertices only:
1. eyeballs a little smaller (EYE_SCALE) and sunk a little into the socket (SINK)
2. the lids slide over the eyeball (upper by REST_UPPER degrees, lower by REST_LOWER), onto a shell
   just outside it, so the eye opening is the reference's: upper lid over the top of the iris
Every shape key layer gets the same offsets. Run once; re-run make_face_shapes.py afterwards.
Head-local coordinates: +x fish's left, +y up, +z front.
"""
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lidlib  # noqa: E402

EYE_SCALE = 0.92
SINK = 0.035
REST_UPPER = -34        # degrees the upper lid comes down over the eye
REST_LOWER = 22         # degrees the lower lid comes up
RINGS_UP, RINGS_LOW = 4, 3
KEEP_OUT = 1.16         # same as LID_KEEP_OUT in make_face_shapes.py
BALL_CENTRE = Vector((0.0, -0.42, 0.0))

head = bpy.data.objects["Head"]
me = head.data
kb = me.shape_keys.key_blocks
for k in kb:
    k.value = 0.0
M = head.matrix_world
Minv = M.inverted()

# ---- 1. eyeballs (radius from the evaluated size before scaling)
eyes = []
for name in ("Eye.L", "Eye.R"):
    e = bpy.data.objects[name]
    r = max(e.dimensions) / 2
    c = Minv @ e.matrix_world.translation
    e.scale = e.scale * EYE_SCALE
    bpy.context.view_layer.update()        # else setting matrix_world below restores the old scale
    c_new = c - (c - BALL_CENTRE).normalized() * SINK
    e.matrix_world.translation = M @ c_new
    eyes.append((np.array(c_new[:]), r * EYE_SCALE))

bm = bmesh.new()
bm.from_mesh(me)
layers = [bm.verts.layers.shape[k.name] for k in kb]
B = bm.verts.layers.shape["Basis"]
partl = bm.faces.layers.float.get("part")
verts = list(bm.verts)
kinds = [{int(round(f[partl])) for f in v.link_faces} for v in verts]
allowed = np.array([0.0 if (2 in k or 3 in k) else 1.0 for k in kinds])
edges = [(e.verts[0].index, e.verts[1].index) for e in bm.edges]

# ---- 2. rest lids
P = np.array([v[B][:] for v in verts])
moved = 0
for c, r in eyes:
    near = np.linalg.norm(P - c, axis=1) < 2.4 * r
    rim = [v.index for v in verts if v.is_boundary and near[v.index]]
    ring = lidlib.rings(len(verts), edges, rim, max(RINGS_UP, RINGS_LOW), near)
    frame = lidlib.eye_frame(P, c, rim)
    newP = lidlib.move_lids(P, c, r, ring, RINGS_UP, RINGS_LOW, frame, allowed, KEEP_OUT,
                            upper_by=REST_UPPER, lower_by=REST_LOWER)
    for i in np.where(np.linalg.norm(newP - P, axis=1) > 1e-7)[0]:
        d = Vector(newP[i] - P[i])
        for layer in layers:
            verts[i][layer] = verts[i][layer] + d
        verts[i].co = verts[i][B]
        moved += 1
    P = newP
bm.to_mesh(me)
bm.free()
me.update()
bpy.ops.wm.save_mainfile()
print("LIDS", {"moved": moved, "eyes": [([round(float(x), 3) for x in c], round(r, 3)) for c, r in eyes]})
