"""
Export a fish .blend to a GLB the app can load, with the settings from
blender/README.md: shape keys kept, no Draco, NLA tracks as named clips.

    /Applications/Blender.app/Contents/MacOS/Blender -b blender/<file>.blend -P blender/export_fish.py
    ... -P blender/export_fish.py -- fish_test.glb     (other file name under public/models/)

Default output is public/models/fish.glb, which the app loads instead of the
procedural fish. Only visible objects are exported, so hide what should stay
out. Reference images are always left out.

Modifiers: Blender's exporter drops the shape keys of any mesh whose modifiers
it applies, so this script bakes them itself. For every visible mesh that has
both modifiers and shape keys, it evaluates the modifier stack once per key
and rebuilds the keys on the evaluated mesh. Meshes with modifiers and no
keys are exported with the modifiers applied. Nothing is saved back.
"""
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
name = argv[0] if argv else "fish.glb"
out = os.path.join(ROOT, "public", "models", name)
os.makedirs(os.path.dirname(out), exist_ok=True)


def visible(obj):
    return not obj.hide_viewport and not obj.hide_get() and obj.visible_get()


def bake_modifiers_with_keys(obj):
    """Replace obj's mesh with its modifier stack applied and the shape keys
    rebuilt on the result. The object itself, its name, parent and children
    stay as they are, so the exporter sees the same hierarchy as before."""
    keys = obj.data.shape_keys.key_blocks
    saved = [(k, k.value) for k in keys]
    # Armature modifiers are skinning, not geometry: leave them out of the bake
    # and put them back afterwards so the exporter writes the skin.
    armatures = [(m.name, m.object, m.use_vertex_groups) for m in obj.modifiers if m.type == "ARMATURE"]
    for m in obj.modifiers:
        if m.type == "ARMATURE":
            m.show_viewport = False
            m.show_render = False

    def evaluated(active=None):
        # Compare by name: Blender hands out a new Python wrapper on every
        # access, so identity checks between key blocks never match.
        for k in keys:
            k.value = 1.0 if k.name == active else 0.0
        # A fresh depsgraph each time: a reused one keeps returning the
        # state it was first evaluated with.
        depsgraph = bpy.context.evaluated_depsgraph_get()
        return bpy.data.meshes.new_from_object(obj.evaluated_get(depsgraph), depsgraph=depsgraph)

    basis_mesh = evaluated(None)
    n = len(basis_mesh.vertices)
    key_positions = []
    for k in keys:
        if k.name == "Basis":
            continue
        mesh = evaluated(k.name)
        if len(mesh.vertices) != n:
            print(f"[export] WARNING: key {k.name} changes topology through the modifiers "
                  f"({len(mesh.vertices)} vs {n} vertices); skipped. Usually a Mirror merge at "
                  f"the centre line: keep centre vertices on the axis in every key.")
        else:
            key_positions.append((k.name, [v.co.copy() for v in mesh.vertices]))
        bpy.data.meshes.remove(mesh)
    for k, v in saved:
        k.value = v

    obj.modifiers.clear()
    obj.data = basis_mesh
    obj.shape_key_add(name="Basis", from_mix=False)
    for name, pos in key_positions:
        nk = obj.shape_key_add(name=name, from_mix=False)
        nk.value = 0.0
        for i, p in enumerate(pos):
            nk.data[i].co = p
    for name, target, use_groups in armatures:
        m = obj.modifiers.new(name, "ARMATURE")
        m.object = target
        m.use_vertex_groups = use_groups
    return obj


for obj in list(bpy.data.objects):
    if obj.type == "EMPTY" and obj.empty_display_type == "IMAGE":
        obj.hide_viewport = True


def uses_node_group(mat):
    return mat and mat.use_nodes and any(n.type == "GROUP" for n in mat.node_tree.nodes)


# Materials built from node groups (procedural generators) make Blender's
# exporter hang for minutes, and glTF could not carry them anyway. Swap
# them for a plain grey material for the export; the file is not saved.
for obj in bpy.data.objects:
    if obj.type != "MESH" or not visible(obj):
        continue
    for i, mat in enumerate(obj.data.materials):
        if uses_node_group(mat):
            stub = bpy.data.materials.new(mat.name + " (export stub)")
            stub.use_nodes = True
            stub.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.8, 0.8, 0.8, 1)
            obj.data.materials[i] = stub
            print(f"[export] WARNING: {obj.name} uses node-group material '{mat.name}', which cannot be "
                  f"exported; replaced with plain grey. Use a Principled BSDF with colours or image textures.")

baked_any = []
for obj in list(bpy.data.objects):
    if obj.type == "MESH" and visible(obj) and obj.modifiers and obj.data.shape_keys and len(obj.data.shape_keys.key_blocks) > 1:
        b = bake_modifiers_with_keys(obj)
        baked_any.append(b.name)
        print(f"[export] baked modifiers into shape keys: {b.name} "
              f"({len(b.data.vertices)} vertices, {len(b.data.shape_keys.key_blocks) - 1} keys)")

has_clips = any(o.animation_data and o.animation_data.nla_tracks for o in bpy.data.objects)

# FACEFISH_NO_GLTF=1: only prepare the scene (shape keys baked, materials stubbed) for another
# exporter that runs next in the same Blender, e.g. blender/export_usd.py for the iOS app.
if os.environ.get("FACEFISH_NO_GLTF"):
    print("[export] scene prepared; glTF export skipped (FACEFISH_NO_GLTF)")
else:
    bpy.ops.export_scene.gltf(
        filepath=out,
        export_format="GLB",
        export_apply=True,
        export_morph=True,
        export_morph_normal=False,
        export_animations=has_clips,
        export_animation_mode="NLA_TRACKS" if has_clips else "ACTIONS",
        export_yup=True,
        export_draco_mesh_compression_enable=False,
        # WebP keeps a 2k texture set around 1-2 MB; the iPad and three.js both read it.
        export_image_format="WEBP",
        export_image_quality=90,
        use_visible=True,
    )
    print(f"[export] {out} ({os.path.getsize(out) // 1024} kB, clips: {'yes' if has_clips else 'no'})")
