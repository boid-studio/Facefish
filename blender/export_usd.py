"""Export the fish as USDZ for the iOS app (RealityKit), matching the glTF export.

    FACEFISH_NO_GLTF=1 Blender -b blender/<fish>.blend \\
        -P blender/export_rest.py -P blender/export_fish.py -P blender/export_usd.py [-- fish.glb]

writes public/models/fish.usdz (next to fish.glb and fish.rig.json). The three scripts run in one
Blender session on the file as loaded; nothing is saved back.
  export_rest.py   rest pose, no animation, fin-wave previews off, rig.json written
  export_fish.py   shape keys rebuilt on the subdivided head (FACEFISH_NO_GLTF skips the .glb)
  export_usd.py    this: hidden objects dropped, other modifiers applied, USDZ written Y-up

Bones and prims keep their names, except that USD does not allow "." in names: Blender writes
"Eye.L" as "Eye_L", "Lid.R" as "Lid_R", "Tail.1" as "Tail_1". Match names ignoring "." and "_".
"""
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
base = os.path.splitext(argv[0] if argv else "fish.glb")[0]
out = os.path.join(ROOT, "public", "models", base + ".usdz")

# 1. drop what the app shouldn't get: hidden objects, reference images, lights and cameras
dropped = []
for o in list(bpy.data.objects):
    if not o.visible_get() or o.type in {"LIGHT", "CAMERA"} or (o.type == "EMPTY" and o.empty_display_type == "IMAGE"):
        dropped.append(o.name)
        bpy.data.objects.remove(o, do_unlink=True)

# 1b. one plain "Fish" group on top, every part a direct child of it. USD makes the Head (which has
#     blend shapes) a SkelRoot, and RealityKit may treat a SkelRoot's subtree as one skinned model;
#     keeping eyes, lids and fins out of it lets the app turn each one on its own. Turning "Fish"
#     turns the whole fish, like turning the Head did. Lids hang off bones in Blender, which USD
#     can't express; as plain children they keep their pivot (their origin) and their axes.
bpy.context.view_layer.update()
head = bpy.data.objects.get("Head")
fish = bpy.data.objects.new("Fish", None)
bpy.context.scene.collection.objects.link(fish)
fish.matrix_world = head.matrix_world.copy() if head else fish.matrix_world
worlds = {o.name: o.matrix_world.copy() for o in bpy.data.objects}
regrouped = []
for o in list(bpy.data.objects):
    if o is fish or (o.type == "MESH" and any(m.type == "ARMATURE" for m in o.modifiers) and o.parent and o.parent.type == "ARMATURE"):
        continue  # skinned meshes stay under their armature
    if o.parent is None or o.parent == head or o.parent_type == "BONE":
        o.parent = fish
        o.parent_type = "OBJECT"
        o.matrix_world = worlds[o.name]
        regrouped.append(o.name)
bpy.context.view_layer.update()

# 2. apply every modifier except the armature (skinning), keeping vertex groups for the skin.
#    Meshes with shape keys were already rebuilt by export_fish.py.
applied = []
dg = bpy.context.evaluated_depsgraph_get()
for o in list(bpy.data.objects):
    if o.type != "MESH":
        continue
    others = [m for m in o.modifiers if m.type != "ARMATURE" and m.show_viewport]
    if not others:
        for m in [m for m in o.modifiers if m.type != "ARMATURE"]:
            o.modifiers.remove(m)
        continue
    if o.data.shape_keys and len(o.data.shape_keys.key_blocks) > 1:
        print(f"[usd] WARNING: {o.name} has shape keys and modifiers; export_fish.py should have baked it")
        continue
    arm = [(m, m.show_viewport) for m in o.modifiers if m.type == "ARMATURE"]
    for m, _ in arm:
        m.show_viewport = False
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(o.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
    o.data = me
    for m in [m for m in o.modifiers if m.type != "ARMATURE"]:
        o.modifiers.remove(m)
    for m, state in arm:
        m.show_viewport = state
    applied.append(o.name)
bpy.context.view_layer.update()

# 2b. textures RealityKit can't read (.psd, .tif, .exr, ...) go in as PNG copies with the same pixels.
#     The USD exporter otherwise packs the source file as is (two 2k PSDs made the USDZ 215 MB).
import tempfile
converted = []
png_dir = tempfile.mkdtemp(prefix="facefish_usd_")
for img in list(bpy.data.images):
    ext = os.path.splitext(img.filepath or img.name)[1].lower()
    if img.source != "FILE" or ext in {".png", ".jpg", ".jpeg"} or not img.users or img.size[0] == 0:
        continue
    w, h = img.size
    png = bpy.data.images.new(os.path.splitext(img.name)[0], w, h, alpha=True)
    png.colorspace_settings.name = img.colorspace_settings.name
    png.alpha_mode = img.alpha_mode
    px = [0.0] * (w * h * 4)
    img.pixels.foreach_get(px)
    png.pixels.foreach_set(px)
    png.filepath_raw = os.path.join(png_dir, png.name + ".png")
    png.file_format = "PNG"
    png.save()
    img.user_remap(png)
    converted.append(img.name)

# 3. USDZ, Y up like glTF (Blender +Y -> -Z, Z -> Y), metres
os.makedirs(os.path.dirname(out), exist_ok=True)
bpy.ops.wm.usd_export(
    filepath=out,
    selected_objects_only=False,
    export_animation=False,
    export_uvmaps=True,
    rename_uvmaps=False,
    export_normals=True,
    export_materials=True,
    generate_preview_surface=True,
    export_subdivision="TESSELLATE",
    export_armatures=True,
    only_deform_bones=False,
    export_shapekeys=True,
    evaluation_mode="VIEWPORT",
    convert_orientation=True,
    export_global_forward_selection="NEGATIVE_Z",
    export_global_up_selection="Y",
    export_custom_properties=False,
    export_lights=False,
    export_cameras=False,
    root_prim_path="/root",
)
print("[usd]", {"file": os.path.relpath(out, ROOT), "kB": os.path.getsize(out) // 1024,
                "modifiers_applied": applied, "dropped": dropped, "regrouped_under_Fish": regrouped,
                "textures_to_png": converted})
