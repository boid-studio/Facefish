"""Put the fish in its rest pose before export_fish.py, and write the rig description next to it.

    Blender -b blender/<fish>.blend -P blender/export_rest.py -P blender/export_fish.py [-- name.glb]

- removes every animation (imported takes, test keys), so the export doesn't freeze the pose of
  whatever frame the file was saved on
- sets every shape key to 0 and every pose bone (lids, tail, fins) to its rest pose
- switches off "FinWave preview" modifiers (the fin wave is for previewing in Blender only) and
  writes their settings to public/models/<name>.rig.json, so the web app and the iOS app run the
  same wave live from each fin's FinWave UV map (exported as the fin's second UV set)
Object transforms are left exactly as they are in the file: the rest pose is what you modelled.

rig.json axes are glTF's (Y up, the fish faces +Z, the fish's left is +X), in each mesh's own space.
"""
import json
import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
glb_name = argv[0] if argv else "fish.glb"
rig_path = os.path.join(ROOT, "public", "models", os.path.splitext(glb_name)[0] + ".rig.json")

cleared = []
for idb in list(bpy.data.objects) + [m.shape_keys for m in bpy.data.meshes if m.shape_keys]:
    ad = getattr(idb, "animation_data", None)
    if ad and (ad.action or len(ad.nla_tracks)):
        cleared.append(idb.name)
    if ad:
        idb.animation_data_clear()
for me in bpy.data.meshes:
    if me.shape_keys:
        for k in me.shape_keys.key_blocks:
            k.value = 0.0
# Rigs hidden in the viewport (to tidy up while sculpting) still belong in the export when a visible
# part hangs off them or is skinned to them; without them the fins come out loose and turned wrong.
shown = []
pending = [o for o in bpy.data.objects if o.visible_get()]
while pending:
    o = pending.pop()
    needs = [m.object for m in o.modifiers if m.type == "ARMATURE" and m.object]
    if o.parent:
        needs.append(o.parent)
    for r in needs:
        if r.type == "ARMATURE" and not r.visible_get():
            r.hide_set(False)
            r.hide_viewport = False
            if r.visible_get():
                shown.append(r.name)
                pending.append(r)
if shown:
    print("[export] hidden rigs included because visible parts use them:", shown)

bones = {}
for o in bpy.data.objects:
    if o.type == "ARMATURE":
        for pb in o.pose.bones:
            pb.location = (0, 0, 0)
            pb.rotation_quaternion = (1, 0, 0, 0)
            pb.rotation_euler = (0, 0, 0)
            pb.scale = (1, 1, 1)
        if o.visible_get():
            bones[o.name] = [b.name for b in o.data.bones]


def blender_to_gltf(v):
    """Blender (Z up) -> glTF (Y up): (x, y, z) -> (x, z, -y)."""
    return [round(v[0], 5), round(v[2], 5), round(-v[1], 5)]


# Image textures whose image is missing or empty (a texture that was never saved or baked, a file
# that moved): the glTF exporter would write a texture with no image, and three.js refuses the whole
# model. Unlink them in this export copy only, and say so.
missing_images = []
for mat in bpy.data.materials:
    if not mat.use_nodes or not mat.users:
        continue
    for node in mat.node_tree.nodes:
        if node.type != "TEX_IMAGE":
            continue
        img = node.image
        empty = img is None
        if img is not None and img.source in {"FILE", "SEQUENCE", "MOVIE"} and not img.packed_file:
            empty = not os.path.exists(bpy.path.abspath(img.filepath, library=img.library)) or img.size[0] == 0
        elif img is not None and img.source == "FILE":
            empty = img.size[0] == 0
        if empty and any(link.from_node == node for link in mat.node_tree.links):
            for link in [l for l in mat.node_tree.links if l.from_node == node]:
                mat.node_tree.links.remove(link)
            missing_images.append(f"{mat.name}: {img.name if img else '(no image)'}")
if missing_images:
    print("[export] WARNING: textures with no image data were left out:", missing_images)

# FinWave previews: read their settings, then switch them off for the export. A preview that is only
# hidden in the viewport still counts (hiding it just stops the ripple in Blender); turn a fin's ripple
# off in the app with Amplitude 0.
fins = {}
for o in bpy.data.objects:
    for m in o.modifiers:
        if not m.name.startswith("FinWave preview"):
            continue
        if o.visible_get() and m.node_group:
            ids = {it.name: it.identifier for it in m.node_group.interface.items_tree
                   if getattr(it, "in_out", "") == "INPUT" and it.name != "Geometry"}
            val = lambda n: getattr(m.properties.inputs, ids[n]).value
            axis = list(val("Axis"))
            length = math.sqrt(sum(a * a for a in axis)) or 1.0
            fins[o.name] = {
                "amplitude": round(float(val("Amplitude")) * length, 5),   # mesh units at the outer edge
                "wavelength": round(float(val("Wavelength")), 4),          # in FinWave U (1 = root to edge)
                "speed": round(float(val("Speed")), 4),                    # waves per second, outward
                "falloff": round(float(val("Falloff")), 4),                # strength = U ** falloff
                "cross": round(float(val("Cross")), 4),                    # phase shift across the fan (V), in waves
                "axis": blender_to_gltf([a / length for a in axis]),       # mesh space, glTF axes (web app)
                "axisUsd": [round(a / length, 5) for a in axis],           # mesh space, Blender/USD axes (iOS)
            }
        m.show_viewport = False
        m.show_render = False
bpy.context.view_layer.update()

rig = {
    "format": "facefish-rig/1",
    "model": glb_name,
    # FACEFISH_SOURCE names the real file when exporting from a temporary copy of an open session
    "source": os.environ.get("FACEFISH_SOURCE") or os.path.basename(bpy.data.filepath),
    "axes": ("axis: glTF mesh space (Y up, the fish faces +Z, its left is +X), for fish.glb. "
             "axisUsd: Blender mesh space (Z up, the fish faces -Y, its left is +X), which fish.usdz keeps "
             "under a single Y-up rotation on /root"),
    "finWave": {
        "uvSet": 1,
        "formula": "offset = axis * amplitude * U^falloff * sin(2*pi*(U/wavelength - speed*t + V*cross))",
        "fins": fins,
    },
    "bones": bones,
}
os.makedirs(os.path.dirname(rig_path), exist_ok=True)
with open(rig_path, "w") as f:
    json.dump(rig, f, indent=2)
print("REST", {"animation_removed_from": cleared, "fin_waves": list(fins), "rig": os.path.relpath(rig_path, ROOT)})
