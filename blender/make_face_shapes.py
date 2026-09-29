"""Generate the Face Cap / ARKit blendshapes on the fish's Head mesh, procedurally.

    /Applications/Blender.app/Contents/MacOS/Blender -b blender/fish_starter8.blend -P blender/make_face_shapes.py

Works on the full (un-mirrored) Head mesh of the pink fish. Regions are found from the mesh itself:
  lower jaw   vertices your jawOpen key moves down
  lips        vertices near the edge of the mouth opening (face attribute "part": 1 mouth, 2 teeth, 3 tongue)
  eyelids     the edge loops around each eye hole; lids slide over the eyeball (lidlib.py)
  brows       the ridge above each eye
_L is the fish's own left (+X), which is where the singer's left lands when the fish is their face.

Every key is rebuilt on each run, except jawOpen, which is yours and is kept as it is.
eyeLook* keys are deliberately not created: the app turns the Eye.L / Eye.R objects for gaze, and it
stops doing that as soon as the model has eyeLook shape keys.
"""
import math

import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lidlib  # noqa: E402

head = bpy.data.objects["Head"]
me = head.data
kb = me.shape_keys.key_blocks
for k in kb:
    k.value = 0.0
NV = len(me.vertices)


def co_of(key):
    a = np.zeros(NV * 3, dtype=np.float64)
    key.data.foreach_get("co", a)
    return a.reshape(NV, 3)


B = co_of(kb["Basis"])
J = co_of(kb["jawOpen"]) - B
X, Y, Z = B[:, 0], B[:, 1], B[:, 2]


def sstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


# ------------------------------------------------------------------ regions
part_face = np.zeros(len(me.polygons))
me.attributes["part"].data.foreach_get("value", part_face)
fin = np.zeros(NV)
me.attributes["fin"].data.foreach_get("value", fin)
vert_parts = [set() for _ in range(NV)]
for p in me.polygons:
    for v in p.vertices:
        vert_parts[v].add(int(round(part_face[p.index])))
exterior = np.array([0 in s for s in vert_parts], dtype=float)
teeth = np.array([2 in s and 0 not in s for s in vert_parts], dtype=float)
tongue = np.array([3 in s and 0 not in s and 2 not in s for s in vert_parts], dtype=float)
movable = (1 - teeth) * (1 - tongue) * (1 - sstep(0.3, 0.7, fin))

# lower jaw: how much jawOpen moves each vertex (downwards)
jd = np.linalg.norm(J, axis=1)
jaw = sstep(0.05, 0.45, jd / jd.max()) * (J[:, 1] < 0.005)

# lip edge: vertices shared by exterior faces and mouth faces
lip_edge = np.array([0 in s and (1 in s or 2 in s or 3 in s) for s in vert_parts])
edge_idx = np.where(lip_edge)[0]
edge_pts = B[edge_idx]
d_lip = np.min(np.linalg.norm(B[:, None, :] - edge_pts[None, :, :], axis=2), axis=1)
lip = (1 - sstep(0.03, 0.24, d_lip)) * movable
lower = sstep(0.08, 0.4, jd / jd.max())
upper_lip = lip * (1 - lower) * (Y > edge_pts[:, 1].min() - 0.05)
lower_lip = lip * lower
cornerL = edge_pts[np.argmax(edge_pts[:, 0])]
cornerR = edge_pts[np.argmin(edge_pts[:, 0])]
mouth_mid = edge_pts.mean(axis=0)


def near(pt, r0, r1):
    return 1 - sstep(r0, r1, np.linalg.norm(B - pt, axis=1))


cornerwL = near(cornerL, 0.04, 0.34) * movable
cornerwR = near(cornerR, 0.04, 0.34) * movable
sideL = sstep(-0.04, 0.14, X)
sideR = sstep(-0.04, 0.14, -X)

# eyes (object centres in Head space) and their radius
Minv = head.matrix_world.inverted()
eyes = {}
for side, name in (("L", "Eye.L"), ("R", "Eye.R")):
    e = bpy.data.objects[name]
    c = Minv @ e.matrix_world.translation
    r = max(e.dimensions) / 2
    eyes[side] = (np.array(c), r)


def eye_regions(side):
    c, r = eyes[side]
    rel = B - c
    dist = np.linalg.norm(rel, axis=1)
    around = (1 - sstep(r + 0.04, r + 0.24, dist)) * exterior_or_socket
    front = sstep(-0.35 * r, 0.1 * r, rel[:, 2])
    up = sstep(0.02, 0.14, rel[:, 1])
    down = sstep(0.02, 0.14, -rel[:, 1])
    lid_up = around * up * front * (1 - sstep(0.3, 0.6, fin))
    lid_low = around * down * front * (1 - sstep(0.3, 0.6, fin))
    h = rel[:, 1]
    lateral = np.abs(rel[:, 0])
    brow = (sstep(r + 0.02, r + 0.14, h) * (1 - sstep(r + 0.28, r + 0.42, h)) * (1 - sstep(0.26, 0.5, lateral))
            * sstep(-0.3, -0.05, rel[:, 2]) * exterior * (1 - sstep(0.3, 0.6, fin)))
    # inner = towards the middle of the face
    toward_mid = np.sign(-c[0]) * rel[:, 0]
    inner = brow * sstep(-0.05, 0.15, toward_mid)
    outer = brow * sstep(-0.05, 0.15, -toward_mid)
    cheek_c = np.array([c[0] * 1.15, (c[1] + cornerL[1]) / 2 - 0.05, (c[2] + cornerL[2]) / 2 - 0.05])
    cheek = near(cheek_c, 0.05, 0.36) * exterior * movable * (1 - lid_low)
    return c, r, lid_up, lid_low, brow, inner, outer, cheek


exterior_or_socket = np.ones(NV) * (1 - teeth) * (1 - tongue)
BALL_C = np.array([0.0, -0.42, 0.0])
_bm = bmesh.new()
_bm.from_mesh(me)
boundary_idx = [v.index for v in _bm.verts if v.is_boundary]
edge_list = [(e.verts[0].index, e.verts[1].index) for e in _bm.edges]
_bm.free()
R = {s: eye_regions(s) for s in ("L", "R")}

# vertex normals (basis)
N = np.zeros(NV * 3)
me.vertices.foreach_get("normal", N)
N = N.reshape(NV, 3)


LID_KEEP_OUT = 1.16    # = KEEP_OUT in sculpt_eyelids.py: lid cage this far out (x eye radius) so the smoothed lid covers the ball


LID_RINGS_UP, LID_RINGS_LOW = 4, 3     # edge loops out from the eye hole that make up each lid


def lid_shape(side, **kw):
    """Blink / wide / squint as offsets (lidlib: the rim of the eye hole is the lid edge)."""
    c, r = R[side][0], R[side][1]
    near_eye = np.linalg.norm(B - c, axis=1) < 2.4 * r
    rim = [i for i in boundary_idx if near_eye[i]]
    ring = lidlib.rings(NV, edge_list, rim, max(LID_RINGS_UP, LID_RINGS_LOW), near_eye)
    frame = lidlib.eye_frame(B, c, rim)
    allowed = exterior_or_socket * (1 - sstep(0.3, 0.6, fin))
    return lidlib.move_lids(B, c, r, ring, LID_RINGS_UP, LID_RINGS_LOW, frame, allowed, LID_KEEP_OUT, **kw) - B


def vec(dx=0.0, dy=0.0, dz=0.0):
    return np.array([dx, dy, dz])


shapes = {}
w_col = lambda w: w[:, None]

for s, sgn, sideW, cornerW, corner in (("L", 1, sideL, cornerwL, cornerL), ("R", -1, sideR, cornerwR, cornerR)):
    c, r, lid_up, lid_low, brow, inner, outer, cheek = R[s]
    # eyes
    shapes[f"eyeBlink_{s}"] = lid_shape(s, upper_to=-22, lower_to=-14)
    shapes[f"eyeWide_{s}"] = lid_shape(s, upper_by=14) + w_col(brow) * vec(0, 0.07, 0)
    shapes[f"eyeSquint_{s}"] = lid_shape(s, upper_by=-12, lower_by=26) + w_col(cheek) * vec(0, 0.06, 0.015)
    # brows
    shapes[f"browDown_{s}"] = w_col(brow) * vec(0, -0.075, 0.01) + w_col(inner) * vec(-sgn * 0.03, -0.02, 0)
    shapes[f"browOuterUp_{s}"] = w_col(outer) * vec(sgn * 0.01, 0.08, 0)
    # cheeks and nose
    shapes[f"cheekSquint_{s}"] = w_col(cheek) * vec(0, 0.055, 0.015)
    sneer_c = np.array([corner[0] * 0.45, corner[1] + 0.2, corner[2] + 0.02])
    shapes[f"noseSneer_{s}"] = w_col(near(sneer_c, 0.04, 0.22) * exterior * movable) * vec(0, 0.06, -0.015)
    # mouth corners
    shapes[f"mouthSmile_{s}"] = w_col(cornerW) * vec(sgn * 0.05, 0.085, -0.03) + w_col(cheek * 0.5) * vec(0, 0.03, 0.01)
    shapes[f"mouthFrown_{s}"] = w_col(cornerW) * vec(sgn * 0.015, -0.085, 0.0)
    shapes[f"mouthDimple_{s}"] = w_col(cornerW) * vec(sgn * 0.03, 0.0, -0.06)
    shapes[f"mouthStretch_{s}"] = w_col(cornerW) * vec(sgn * 0.08, -0.03, -0.01)
    shapes[f"mouthPress_{s}"] = w_col(upper_lip * sideW) * vec(0, -0.025, -0.01) + w_col(lower_lip * sideW) * vec(0, 0.025, -0.01)
    shapes[f"mouthUpperUp_{s}"] = w_col(upper_lip * sideW) * vec(0, 0.07, 0.01)
    shapes[f"mouthLowerDown_{s}"] = w_col(lower_lip * sideW) * vec(0, -0.075, 0.01)

# both sides at once
inner_both = R["L"][5] + R["R"][5]
shapes["browInnerUp"] = w_col(inner_both) * vec(0, 0.085, 0.01)
cheek_both = np.clip(R["L"][7] + R["R"][7], 0, 1)
shapes["cheekPuff"] = w_col(np.clip(cheek_both + lip * 0.35, 0, 1)) * (N * 0.09)
lips_all = np.clip(upper_lip + lower_lip, 0, 1)
shapes["mouthFunnel"] = w_col(lips_all) * np.stack([-X * 0.2, np.zeros(NV), np.full(NV, 0.08)], axis=1) \
    + w_col(upper_lip) * vec(0, 0.035, 0) + w_col(lower_lip) * vec(0, -0.035, 0)
shapes["mouthPucker"] = w_col(lips_all) * np.stack([-X * 0.35, np.zeros(NV), np.full(NV, 0.1)], axis=1) \
    + w_col(upper_lip) * vec(0, -0.01, 0) + w_col(lower_lip) * vec(0, 0.02, 0)
shapes["mouthLeft"] = w_col(lips_all) * vec(0.09, 0, 0)
shapes["mouthRight"] = w_col(lips_all) * vec(-0.09, 0, 0)
shapes["mouthRollUpper"] = w_col(upper_lip) * vec(0, -0.035, -0.05)
shapes["mouthRollLower"] = w_col(lower_lip) * vec(0, 0.035, -0.05)
shapes["mouthShrugUpper"] = w_col(upper_lip) * vec(0, 0.045, 0.02)
shapes["mouthShrugLower"] = w_col(lower_lip) * vec(0, 0.05, 0.03) + w_col(jaw * 0.4) * vec(0, 0.02, 0.02)
shapes["mouthClose"] = -J * w_col(lower_lip)
shapes["jawForward"] = w_col(jaw) * vec(0, 0, 0.08)
shapes["jawLeft"] = w_col(jaw) * vec(0.09, 0, 0)
shapes["jawRight"] = w_col(jaw) * vec(-0.09, 0, 0)
tongue_front = tongue * sstep(Z.min(), Z.max(), Z)
shapes["tongueOut"] = w_col(tongue * sstep(0.2, 0.6, Z)) * vec(0, -0.05, 0.24)

# ------------------------------------------------------------------ strengths
# a cartoon fish needs big expressions: these scale the shapes above (1 = as defined)
STRENGTH = {
    "browInnerUp": 1.9, "browDown_L": 1.7, "browDown_R": 1.7, "browOuterUp_L": 1.9, "browOuterUp_R": 1.9,
    "cheekPuff": 1.45, "cheekSquint_L": 1.8, "cheekSquint_R": 1.8, "noseSneer_L": 1.8, "noseSneer_R": 1.8,
    "mouthSmile_L": 1.7, "mouthSmile_R": 1.7, "mouthFrown_L": 1.6, "mouthFrown_R": 1.6,
    "mouthDimple_L": 1.6, "mouthDimple_R": 1.6, "mouthStretch_L": 1.6, "mouthStretch_R": 1.6,
    "mouthUpperUp_L": 1.7, "mouthUpperUp_R": 1.7, "mouthLowerDown_L": 1.7, "mouthLowerDown_R": 1.7,
    "mouthPress_L": 1.6, "mouthPress_R": 1.6, "mouthLeft": 1.5, "mouthRight": 1.5,
    "mouthRollUpper": 1.6, "mouthRollLower": 1.6, "mouthShrugUpper": 1.6, "mouthShrugLower": 1.6,
}
for name, k in STRENGTH.items():
    shapes[name] = shapes[name] * k

# ------------------------------------------------------------------ write the keys in Face Cap order
FACECAP = [
    "browInnerUp", "browDown_L", "browDown_R", "browOuterUp_L", "browOuterUp_R",
    "eyeBlink_L", "eyeBlink_R", "eyeSquint_L", "eyeSquint_R", "eyeWide_L", "eyeWide_R",
    "cheekPuff", "cheekSquint_L", "cheekSquint_R", "noseSneer_L", "noseSneer_R",
    "jawOpen", "jawForward", "jawLeft", "jawRight",
    "mouthFunnel", "mouthPucker", "mouthLeft", "mouthRight",
    "mouthRollUpper", "mouthRollLower", "mouthShrugUpper", "mouthShrugLower", "mouthClose",
    "mouthSmile_L", "mouthSmile_R", "mouthFrown_L", "mouthFrown_R",
    "mouthDimple_L", "mouthDimple_R", "mouthUpperUp_L", "mouthUpperUp_R",
    "mouthLowerDown_L", "mouthLowerDown_R", "mouthPress_L", "mouthPress_R",
    "mouthStretch_L", "mouthStretch_R", "tongueOut",
]
report = {}
for name in FACECAP:
    if name == "jawOpen":
        continue
    delta = shapes[name]
    key = kb.get(name) or head.shape_key_add(name=name, from_mix=False)
    key.value = 0.0
    key.relative_key = kb["Basis"]
    key.data.foreach_set("co", (B + delta).ravel())
    mag = np.linalg.norm(delta, axis=1)
    moved = mag > 0.002
    report[name] = {
        "moved": int(moved.sum()),
        "max": round(float(mag.max()), 3),
        "left_right": [round(float(mag[X > 0.02].sum()), 2), round(float(mag[X < -0.02].sum()), 2)],
    }
# keep Face Cap order in the key list
order = ["Basis"] + [n for n in FACECAP if n in kb]
for target_index, name in enumerate(order):
    idx = kb.find(name)
    head.active_shape_key_index = idx
    while idx > target_index:
        bpy.context.view_layer.objects.active = head
        bpy.ops.object.shape_key_move(type="UP")
        idx -= 1
head.active_shape_key_index = 0
bpy.ops.wm.save_mainfile()
print("SHAPES", len([k for k in kb]) - 1, report)
