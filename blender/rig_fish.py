"""Build the armature for the fish with separate fin meshes (fish_starter9 and later).

    /Applications/Blender.app/Contents/MacOS/Blender -b blender/fish_starter9.blend -P blender/rig_fish.py

Rebuilds the "Rig" from scratch each time; re-run blender/make_swim.py afterwards, because the
rebuild removes the rig's animation.

Bones (fish faces -Y, up +Z):
  Root      body and eyes; vertical, so its frame matches the world frame
  Tail      vertical at the tail stalk: rotating about its own Y axis swings the tail sideways,
            which is what the app does to sway it; the stalk bends smoothly onto it
  Dorsal    the dorsal fin
  Fin.L/R   the pectoral fins, pointing out along each fin
  Anal      the small fin under the tail stalk
Fin meshes (made by make_fins.py) ride on their bone; the object property "fin_bone" names it.
The Head mesh is skinned to Root and Tail; the face itself is driven by shape keys.
rig_fish_v1.py is the older version for fish_starter7/8, whose fins were part of the Head mesh.
"""
import bpy
from mathutils import Vector

scene = bpy.context.scene
head = bpy.data.objects["Head"]
me = head.data
for k in me.shape_keys.key_blocks:
    k.value = 0.0
fins = [o for o in bpy.data.objects if o.type == "MESH" and "fin_bone" in o.keys()]


def fin_frame(obj):
    """Root centre and mean direction of a fin mesh (root = first rows of its UV v ~ 0)."""
    pts = [obj.matrix_world @ v.co for v in obj.data.vertices]
    c = sum(pts, Vector()) / len(pts)
    # the root line is the part of the fin closest to the body centre
    body_c = Vector((0, 0.03, -0.43))
    near = sorted(pts, key=lambda p: (p - body_c).length)[: max(6, len(pts) // 12)]
    root = sum(near, Vector()) / len(near)
    return root, (c - root).normalized(), (c - root).length


# ---------------------------------------------------------------- armature
old = bpy.data.objects.get("Rig")
if old:
    for child in list(old.children):
        mw = child.matrix_world.copy()
        child.parent = None
        child.matrix_world = mw
    bpy.data.objects.remove(old, do_unlink=True)
arm = bpy.data.armatures.new("Rig")
rig = bpy.data.objects.new("Rig", arm)
scene.collection.objects.link(rig)
rig.show_in_front = True
for o in bpy.context.view_layer.objects:
    o.select_set(False)
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="EDIT")


def bone(name, h, t, parent=None):
    b = arm.edit_bones.new(name)
    b.head = Vector(h)
    b.tail = Vector(t)
    b.roll = 0.0
    if parent:
        b.parent = arm.edit_bones[parent]
    return b


body_c = Vector((0.0, 0.03, -0.43))
bone("Root", body_c, body_c + Vector((0, 0, 0.5)))
TAIL_Y = 0.86
bone("Tail", Vector((0, TAIL_Y, -0.37)), Vector((0, TAIL_Y, 0.03)), "Root")
for f in fins:
    name = f["fin_bone"]
    if name in ("Root", "Tail"):
        continue
    root, d, reach = fin_frame(f)
    if name == "Dorsal":
        bone(name, (0, root.y, root.z), (0, root.y, root.z + 0.4), "Root")
    else:
        bone(name, root, root + d * max(0.25, reach), "Root")
bpy.ops.object.mode_set(mode="OBJECT")
for pb in rig.pose.bones:
    pb.rotation_mode = "XYZ"

# ---------------------------------------------------------------- Head skin: Root + Tail
for vg in list(head.vertex_groups):
    head.vertex_groups.remove(vg)
g_root = head.vertex_groups.new(name="Root")
g_tail = head.vertex_groups.new(name="Tail")


def smooth(a, b, x):
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


M = head.matrix_world
basis = me.shape_keys.key_blocks["Basis"].data
nt = 0
for v in me.vertices:
    y = (M @ basis[v.index].co).y
    t = smooth(TAIL_Y - 0.3, TAIL_Y + 0.22, y)
    if t > 0:
        g_tail.add([v.index], t, "REPLACE")
        nt += 1
    if t < 1:
        g_root.add([v.index], 1 - t, "REPLACE")
mod = head.modifiers.get("Armature") or head.modifiers.new("Armature", "ARMATURE")
mod.object = rig
mod.use_vertex_groups = True
order = [n for n in ("Mirror", "Armature", "Subdivision") if n in head.modifiers]
for i, name in enumerate(order):
    bpy.ops.object.select_all(action="DESELECT")
    head.select_set(True)
    bpy.context.view_layer.objects.active = head
    bpy.ops.object.modifier_move_to_index(modifier=name, index=i)
mw = head.matrix_world.copy()
head.parent = rig
head.parent_type = "OBJECT"
head.matrix_world = mw


# ---------------------------------------------------------------- eyes and fins ride on bones
def to_bone(obj, bone_name):
    mw = obj.matrix_world.copy()
    obj.parent = rig
    obj.parent_type = "BONE"
    obj.parent_bone = bone_name
    obj.matrix_world = mw


for n in ("Eye.L", "Eye.R"):
    to_bone(bpy.data.objects[n], "Root")
for f in fins:
    to_bone(f, f["fin_bone"])
bpy.context.view_layer.update()

# sanity: swinging the tail moves the tail fin, not the face
tail_fin = next((f for f in fins if f["fin_bone"] == "Tail"), None)
before = tail_fin.matrix_world.translation.copy() if tail_fin else None
rig.pose.bones["Tail"].rotation_euler = (0, 0.5, 0)
bpy.context.view_layer.update()
moved = (tail_fin.matrix_world.translation - before).length if tail_fin else 0
rig.pose.bones["Tail"].rotation_euler = (0, 0, 0)
bpy.context.view_layer.update()
bpy.ops.wm.save_mainfile()
print("RIG", {"bones": [b.name for b in arm.bones], "fins": {f.name: f["fin_bone"] for f in fins},
              "tail_weighted": nt, "tail_fin_moved": round(moved, 3)})
