"""Run inside Blender on the open fish (Text Editor > Open > Run Script, or through the Blender MCP)
to save a self-contained copy for tools/export-fish.sh. See docs/fish-export.md.

Command-line Blender can't read files in Google Drive (macOS privacy), and a copy saved elsewhere
would lose its relative texture paths, so the copy gets every texture packed in. The open file is
left as it was: textures are packed only while the copy is written and unpacked again, and the copy
is saved with copy=True, so the open file keeps its name and saved state.
"""
import bpy

DEST = globals().get("DEST", "/tmp/facefish_export.blend")

packed = []
for image in bpy.data.images:
    if image.source == "FILE" and not image.packed_file and image.filepath:
        try:
            image.pack()
            packed.append(image.name)
        except RuntimeError:
            print(f"[export copy] could not pack {image.name} ({image.filepath})")
bpy.ops.wm.save_as_mainfile(filepath=DEST, copy=True)
for name in packed:
    image = bpy.data.images.get(name)
    if image and image.packed_file:
        image.unpack(method="REMOVE")
print(f"[export copy] saved {DEST} with {len(packed)} textures packed in")
