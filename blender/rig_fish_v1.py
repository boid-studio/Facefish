"""Build the armature, skin weights and eye parenting for fish_starter7/8 (fins part of the Head mesh).

    /Applications/Blender.app/Contents/MacOS/Blender -b blender/fish_starter8.blend -P blender/rig_fish_v1.py

Rebuilds the "Rig" from scratch each time (the fin attributes on the Head mesh say where the fins are).
Works on the mirrored half mesh (fish_starter7) and on the full mesh with face shapes (fish_starter8).
Re-run blender/make_swim.py afterwards: rebuilding the rig removes its animation.
For fish_starter9 and later, with separate fin meshes, use rig_fish.py.

Bones (armature "Rig", fish faces -Y, up +Z):
  Root          body, head and eyes; vertical, so its frame matches the world frame
  Tail          vertical at the tail stalk: rotating about its own Y axis swings the tail sideways
  Dorsal        dorsal fin
  Fin.L/Fin.R   pectoral fins, pointing out along the fin
  Pelvic.L/.R   pelvic fins
The Head mesh keeps its shape keys (jawOpen etc.); the face is driven by those, not by bones.
"""
from collections import defaultdict

import bpy
from mathutils import Vector

scene = bpy.context.scene
head = bpy.data.objects["Head"]
me = head.data
kb = me.shape_keys.key_blocks
kb["jawOpen"].value = 0.0
basis = kb["Basis"].data
M = head.matrix_world          # local -> world (the Head object is rotated 90 degrees on X)
NV = len(me.vertices)


def fattr(name):
    a = me.attributes[name]
    vals = [0.0] * NV
    a.data.foreach_get("value", vals)
    return vals


def vattr(name):
    a = me.attributes[name]
    flat = [0.0] * (NV * 3)
    a.data.foreach_get("vector", flat)
    return [Vector(flat[i * 3:i * 3 + 3]) for i in range(NV)]


fin = fattr("fin")
fin_r = fattr("fin_r")
fan_c = vattr("fan_c")

# group fin vertices by their fan centre: one group per fin
groups = defaultdict(set)
for v in range(NV):
    if fin[v] > 0.5:
        c = fan_c[v]
        key = (round(abs(c.x), 2), round(c.y, 2), round(c.z, 2))
        groups[key].add(v)
fins = {}
for key, vs in groups.items():
    c = sum((basis[v].co for v in vs), Vector()) / len(vs)
    fins[len(fins)] = (c, vs)
dorsal = max(fins.values(), key=lambda t: t[0].y)
tail = min(fins.values(), key=lambda t: t[0].z)
others = [t for t in fins.values() if t is not dorsal and t is not tail]
pec_all = max(others, key=lambda t: t[0].z)[1]
pel_all = min(others, key=lambda t: t[0].z)[1]


def side(vs, sign):
    part = {v for v in vs if basis[v].co.x * sign > 1e-4}
    return (sum((basis[v].co for v in part), Vector()) / len(part), part) if part else None


pectoral, pelvic = side(pec_all, 1), side(pel_all, 1)
pectoral_r, pelvic_r = side(pec_all, -1), side(pel_all, -1)


def root_of(vs):
    # the fin's base: its vertices with the smallest fin_r
    lo = sorted(vs, key=lambda v: fin_r[v])[: max(4, len(vs) // 6)]
    return sum((basis[v].co for v in lo), Vector()) / len(lo)


def tip_of(vs):
    hi = sorted(vs, key=lambda v: -fin_r[v])[: max(4, len(vs) // 6)]
    return sum((basis[v].co for v in hi), Vector()) / len(hi)


W = lambda p: M @ p           # local point -> world point

# ---------------------------------------------------------------- armature
old = bpy.data.objects.get("Rig")
if old:
    bpy.data.objects.remove(old, do_unlink=True)
arm = bpy.data.armatures.new("Rig")
rig = bpy.data.objects.new("Rig", arm)
scene.collection.objects.link(rig)
rig.show_in_front = True
arm.display_type = "OCTAHEDRAL"
for o in bpy.context.view_layer.objects:
    o.select_set(False)
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="EDIT")


def bone(name, h, t, parent=None, roll=0.0):
    b = arm.edit_bones.new(name)
    b.head = Vector(h)
    b.tail = Vector(t)
    b.roll = roll
    if parent:
        b.parent = arm.edit_bones[parent]
    return b


body_c = W(Vector((0.0, -0.1, 0.0)))
bone("Root", body_c, body_c + Vector((0, 0, 0.5)))
tail_root = W(root_of(tail[1]))
tail_pivot = Vector((0.0, tail_root.y - 0.18, tail_root.z))   # a little forward, in the tail stalk
bone("Tail", tail_pivot, tail_pivot + Vector((0, 0, 0.4)), "Root")
d_root, d_tip = W(root_of(dorsal[1])), W(tip_of(dorsal[1]))
bone("Dorsal", Vector((0, d_root.y, d_root.z)), Vector((0, d_tip.y, d_tip.z)), "Root")
p_root, p_tip = W(root_of(pectoral[1])), W(tip_of(pectoral[1]))
bone("Fin.L", p_root, p_tip, "Root")
bone("Fin.R", Vector((-p_root.x, p_root.y, p_root.z)), Vector((-p_tip.x, p_tip.y, p_tip.z)), "Root")
v_root, v_tip = W(root_of(pelvic[1])), W(tip_of(pelvic[1]))
bone("Pelvic.L", v_root, v_tip, "Root")
bone("Pelvic.R", Vector((-v_root.x, v_root.y, v_root.z)), Vector((-v_tip.x, v_tip.y, v_tip.z)), "Root")
bpy.ops.object.mode_set(mode="OBJECT")
for pb in rig.pose.bones:
    pb.rotation_mode = "XYZ"

# ---------------------------------------------------------------- weights (half mesh; Mirror makes .R)
for vg in list(head.vertex_groups):
    head.vertex_groups.remove(vg)
vg = {n: head.vertex_groups.new(name=n) for n in ("Root", "Tail", "Dorsal", "Fin.L", "Fin.R", "Pelvic.L", "Pelvic.R")}


def smooth(a, b, x):
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


tail_local_root_z = root_of(tail[1]).z
weights = defaultdict(dict)
for v in range(NV):
    p = basis[v].co
    w = {}
    # tail: the stalk bends gradually, the tail fin moves fully
    t = smooth(tail_local_root_z + 0.30, tail_local_root_z - 0.02, p.z)
    if v in tail[1]:
        t = 1.0
    if t > 0:
        w["Tail"] = t
    if v in dorsal[1]:
        w["Dorsal"] = smooth(0.0, 0.35, fin_r[v])
    if v in pectoral[1]:
        w["Fin.L"] = smooth(0.0, 0.3, fin_r[v])
    if v in pelvic[1]:
        w["Pelvic.L"] = 1.0
    if pectoral_r and v in pectoral_r[1]:
        w["Fin.R"] = smooth(0.0, 0.3, fin_r[v])
    if pelvic_r and v in pelvic_r[1]:
        w["Pelvic.R"] = 1.0
    s = sum(w.values())
    if s > 1.0:
        w = {k: x / s for k, x in w.items()}
        s = 1.0
    if s < 1.0:
        w["Root"] = 1.0 - s
    for name, x in w.items():
        vg[name].add([v], x, "REPLACE")
counts = {n: 0 for n in vg}
for v in me.vertices:
    for g in v.groups:
        if g.weight > 0.01:
            counts[head.vertex_groups[g.group].name] += 1

mir = head.modifiers.get("Mirror")
if mir:
    mir.use_mirror_vertex_groups = True
mod = head.modifiers.get("Armature") or head.modifiers.new("Armature", "ARMATURE")
mod.object = rig
mod.use_vertex_groups = True
mod.use_deform_preserve_volume = False
# Mirror -> Armature -> Subdivision: deform the cage, then smooth
order = [n for n in ("Mirror", "Armature", "Subdivision") if n in head.modifiers]
for i, name in enumerate(order):
    if True:
        bpy.ops.object.select_all(action="DESELECT")
        head.select_set(True)
        bpy.context.view_layer.objects.active = head
        bpy.ops.object.modifier_move_to_index(modifier=name, index=i)

# parent the mesh to the rig, keeping its transform
mw = head.matrix_world.copy()
head.parent = rig
head.parent_type = "OBJECT"
head.matrix_world = mw

# eyes ride on the Root bone
for name in ("Eye.L", "Eye.R"):
    eye = bpy.data.objects[name]
    mw = eye.matrix_world.copy()
    eye.parent = rig
    eye.parent_type = "BONE"
    eye.parent_bone = "Root"
    eye.matrix_world = mw
bpy.context.view_layer.update()

# sanity: bending the tail must move the tail fin and leave the face alone
dg = bpy.context.evaluated_depsgraph_get()


def eval_bbox():
    dg.update()
    ev = head.evaluated_get(dg)
    m = ev.to_mesh()
    pts = [ev.matrix_world @ v.co for v in m.vertices]
    ev.to_mesh_clear()
    return pts


rest = eval_bbox()
rig.pose.bones["Tail"].rotation_euler = (0, 0.5, 0)
bent = eval_bbox()
rig.pose.bones["Tail"].rotation_euler = (0, 0, 0)
moved_tail = max((a - b).length for a, b in zip(rest, bent) if a.y > tail_root.y)
moved_face = max((a - b).length for a, b in zip(rest, bent) if a.y < -0.6)
bpy.ops.wm.save_mainfile()
print("STEPC", {"bones": [b.name for b in arm.bones], "weights": counts,
                "tail_test": {"tail_moved": round(moved_tail, 3), "face_moved": round(moved_face, 4)},
                "modifiers": [m.name for m in head.modifiers],
                "eye_parent": (bpy.data.objects["Eye.L"].parent.name, bpy.data.objects["Eye.L"].parent_bone)})
