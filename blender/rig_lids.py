"""Lid bones and mirrored right eye/lid for David's fish, in the open file or headless:

    /Applications/Blender.app/Contents/MacOS/Blender -b blender/<file>.blend -P blender/rig_lids.py

The script does not save; in the GUI save yourself, headless add --python-expr "import bpy; bpy.ops.wm.save_mainfile()".

1. Eye.R: rebuilt as an exact mirror of Eye.L, so both eyes have the same local axes (gaze turns
   them the same way; the app rotates each eye about its own axes) and the same shape.
2. Eyelid.R: a mirrored copy of Eyelid.L (no negative scale; normals fixed). A Mirror modifier on
   Eyelid.L is removed, since the right lid is now its own object. An existing Eyelid.R is kept,
   renamed "Eyelid.R old" and hidden.
3. Armature "EyelidRig", parented to Head, with bones Lid.L and Lid.R at each lid's pivot, their X
   axis on the lid's X axis. Each lid is parented to its bone, keeping its place. Rotating a bone
   about X turns its lid exactly like rotating the object did; the same sign closes both lids.
"""
import bmesh
import bpy
from mathutils import Matrix, Vector

S = Matrix.Diagonal((-1.0, 1.0, 1.0, 1.0))   # mirror across the fish's centre plane (world X)
report = {}
scene = bpy.context.scene
if bpy.context.mode != "OBJECT":
    bpy.ops.object.mode_set(mode="OBJECT")
head = bpy.data.objects["Head"]
lid_l = bpy.data.objects["Eyelid.L"]

# ---- 1. Eye.R = exact mirror of Eye.L: same local axes (gaze turns both the same way) and the
#      same shape (the old right eyeball stuck out a little further than the left)
eye_l = bpy.data.objects.get("Eye.L")
eye_r = bpy.data.objects.get("Eye.R")


def mirrored_mesh(src):
    me = src.data.copy()
    me.transform(S)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
    bm.to_mesh(me)
    bm.free()
    me.update()
    return me


if eye_l is not None and eye_r is not None:
    old_mesh = eye_r.data.name
    eye_r.data = mirrored_mesh(eye_l)
    eye_r.data.name = "Eye.R"
    eye_r.matrix_world = S @ eye_l.matrix_world @ S
    bpy.context.view_layer.update()
    report["Eye.R"] = f"rebuilt as a mirror of Eye.L (old mesh '{old_mesh}' kept until the file is saved)"
    report["Eye.R_rotation"] = [round(x, 4) for x in eye_r.rotation_euler]

# ---- 2. Eyelid.R as a mirrored copy of Eyelid.L
for m in list(lid_l.modifiers):
    if m.type == "MIRROR":
        lid_l.modifiers.remove(m)
        report["Eyelid.L"] = "Mirror modifier removed (the right lid is its own object now)"
old = bpy.data.objects.get("Eyelid.R")
if old is not None:
    old.name = "Eyelid.R old"
    old.hide_set(True)
    old.hide_render = True
    report["old Eyelid.R"] = "renamed 'Eyelid.R old' and hidden"
lid_r = lid_l.copy()
lid_r.name = "Eyelid.R"
for coll in lid_l.users_collection:
    coll.objects.link(lid_r)
lid_r.data = mirrored_mesh(lid_l)             # local x flipped, faces turned the right way out
lid_l_world = lid_l.matrix_world.copy()
lid_r_world = S @ lid_l_world @ S             # two reflections: a proper rotation, no negative scale
lid_r.parent = None
lid_r.matrix_world = lid_r_world

# ---- 3. Armature with one bone per lid
arm = bpy.data.objects.get("EyelidRig")
if arm is None:
    arm = bpy.data.objects.new("EyelidRig", bpy.data.armatures.new("EyelidRig"))
    for coll in head.users_collection:
        coll.objects.link(arm)
arm.parent = head
arm.matrix_parent_inverse = Matrix.Identity(4)
arm.matrix_basis = Matrix.Identity(4)
arm.data.display_type = "STICK"
arm.show_in_front = True
bpy.context.view_layer.update()
to_arm = arm.matrix_world.inverted()

for o in bpy.context.selected_objects:
    o.select_set(False)
arm.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="EDIT")
eb = arm.data.edit_bones
for name in ("Lid.L", "Lid.R"):
    if name in eb:
        eb.remove(eb[name])
BONE_LEN = 0.12
for name, world in (("Lid.L", lid_l_world), ("Lid.R", lid_r_world)):
    m = to_arm @ world
    x, y, z = (m.to_3x3().normalized().col[i] for i in range(3))
    b = eb.new(name)
    b.head = m.translation
    b.tail = m.translation + y * BONE_LEN
    b.align_roll(z)
bpy.ops.object.mode_set(mode="OBJECT")
for pb in arm.pose.bones:
    pb.rotation_mode = "XYZ"
    pb.rotation_euler = (0, 0, 0)
bpy.context.view_layer.update()

# parent each lid to its bone, keeping where it is
for lid, bone, world in ((lid_l, "Lid.L", lid_l_world), (lid_r, "Lid.R", lid_r_world)):
    lid.parent = arm
    lid.parent_type = "BONE"
    lid.parent_bone = bone
    lid.matrix_parent_inverse = Matrix.Identity(4)
    bpy.context.view_layer.update()
    lid.matrix_world = world
bpy.context.view_layer.update()

# checks: bone X matches lid X, lids didn't move, a bone turn turns the lid about its own X
checks = {}
for lid, bone, world in ((lid_l, "Lid.L", lid_l_world), (lid_r, "Lid.R", lid_r_world)):
    bm_world = arm.matrix_world @ arm.pose.bones[bone].matrix
    bx = bm_world.to_3x3().normalized().col[0]
    lx = lid.matrix_world.to_3x3().normalized().col[0]
    moved = (lid.matrix_world.translation - world.translation).length
    checks[bone] = {"x_axes_dot": round(bx.dot(lx), 5), "lid_moved": round(moved, 6),
                    "pivot_gap": round((bm_world.translation - lid.matrix_world.translation).length, 6)}
mirror_err = (lid_r.matrix_world.translation - (S @ lid_l.matrix_world).translation).length
report["checks"] = checks
report["lid_R_mirror_error"] = round(mirror_err, 6)
report["Eyelid.R_scale"] = [round(s, 4) for s in lid_r.scale]
arm.select_set(False)
result = report
print("RIG", report)
