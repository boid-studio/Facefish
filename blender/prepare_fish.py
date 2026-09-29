"""
Prepare a fish .blend for the app, without touching the sculpt:

  - adds any of the 52 Face Cap shape keys the Head mesh is missing (existing
    keys and their sculpts are kept),
  - adds the reference images from blender/reference/ (see add_references.py),
  - repoints every texture used by a visible object to blender/textures/<same
    file name> when that exists, so the file no longer depends on a path outside
    the repo (put a copy there first; 2048 px is plenty for the iPad),

then saves the file in place.

    /Applications/Blender.app/Contents/MacOS/Blender -b blender/<file>.blend -P blender/prepare_fish.py
"""
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from add_facecap_shapekeys import FACECAP_SHAPES  # noqa: E402
from add_references import add_references  # noqa: E402


def head_object():
    for name in ("Head", "head", "FishHead", "Face"):
        obj = bpy.data.objects.get(name)
        if obj and obj.type == "MESH" and obj.visible_get():
            return obj
    raise RuntimeError("No visible mesh named Head")


def add_shape_keys(obj):
    if obj.data.shape_keys is None:
        obj.shape_key_add(name="Basis", from_mix=False)
    existing = {k.name for k in obj.data.shape_keys.key_blocks}
    added = 0
    for name in FACECAP_SHAPES:
        if name in existing:
            continue
        key = obj.shape_key_add(name=name, from_mix=False)
        key.value = 0.0
        added += 1
    print(f"[prepare] {obj.name}: {added} shape keys added, {len(existing) - 1} kept")


def relink_textures():
    tex_dir = os.path.join(HERE, "textures")
    relinked, missing = [], []
    for obj in bpy.data.objects:
        if obj.type != "MESH" or not obj.visible_get():
            continue
        for mat in obj.data.materials:
            if not mat or not mat.use_nodes:
                continue
            for node in mat.node_tree.nodes:
                img = getattr(node, "image", None)
                if not img or img.packed_file:
                    continue
                local = os.path.join(tex_dir, os.path.basename(img.filepath))
                current = bpy.path.abspath(img.filepath)
                if os.path.exists(local):
                    if os.path.abspath(current) != os.path.abspath(local):
                        img.filepath = bpy.path.relpath(local)
                        img.reload()
                        relinked.append(f"{img.name} -> {img.filepath}")
                elif not os.path.exists(current):
                    missing.append(f"{img.name}: {current}")
    for r in relinked:
        print(f"[prepare] relinked {r}")
    for m in missing:
        print(f"[prepare] WARNING: texture not found and no copy in blender/textures/: {m}")


head = head_object()
add_shape_keys(head)
add_references()
relink_textures()
bpy.ops.wm.save_mainfile()
print(f"[prepare] saved {bpy.data.filepath}")
