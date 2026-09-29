"""
Add the reference images in blender/reference/ to a fish .blend as image
empties, each aligned to the view it was drawn from:

    top.png          seen from above (numpad 7)
    bottom.webp      seen from below (ctrl+numpad 7)
    front.png        seen from the front (numpad 1)
    perspective.webp a free board beside the model, for perspective views

The aligned ones only show in their own orthographic view, behind the model,
at half opacity. Images are packed into the file.

    /Applications/Blender.app/Contents/MacOS/Blender -b blender/fish_starter.blend -P blender/add_references.py
    ... -P blender/add_references.py -- --verify   also renders the three views to /tmp for checking
"""
import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
REF_DIR = os.path.join(HERE, "reference")

# Model is about 2.9 units nose to tail; the fish fills ~85% of the top image.
TOP_WIDTH = 3.4
FRONT_WIDTH = 3.2

# name, file, location, rotation (deg, XYZ), width, axis-aligned only
REFERENCES = [
    ("Ref Top", "top.png", (0, 0, 0), (0, 0, -90), TOP_WIDTH, True),
    ("Ref Bottom", "bottom.webp", (0, 0, 0), (180, 0, -90), TOP_WIDTH, True),
    ("Ref Front", "front.png", (0, 0, 0), (90, 0, 0), FRONT_WIDTH, True),
    ("Ref Perspective", "perspective.webp", (3.6, 0.6, 0.2), (90, 0, 0), 2.6, False),
]


def add_references():
    coll = bpy.data.collections.get("Reference")
    if coll is None:
        coll = bpy.data.collections.new("Reference")
        bpy.context.scene.collection.children.link(coll)

    for name, file, loc, rot, width, aligned in REFERENCES:
        old = bpy.data.objects.get(name)
        if old:
            bpy.data.objects.remove(old, do_unlink=True)
        path = os.path.join(REF_DIR, file)
        img = bpy.data.images.load(path, check_existing=True)
        img.pack()

        empty = bpy.data.objects.new(name, None)
        empty.empty_display_type = "IMAGE"
        empty.data = img
        empty.empty_display_size = width
        empty.empty_image_offset = (-0.5, -0.5)
        empty.location = loc
        empty.rotation_euler = tuple(math.radians(a) for a in rot)
        empty.empty_image_depth = "BACK"
        empty.use_empty_image_alpha = True
        empty.color = (1, 1, 1, 0.55 if aligned else 1.0)
        empty.show_empty_image_orthographic = True
        empty.show_empty_image_perspective = not aligned
        empty.show_empty_image_only_axis_aligned = aligned
        empty.hide_select = aligned  # so sculpt clicks never grab it
        empty.hide_render = True
        coll.objects.link(empty)
    print(f"[reference] {len(REFERENCES)} reference images added")


def verify(out_dir):
    """Render the three aligned views with textured planes standing in for the
    empties (empties never render), so the orientation can be checked."""
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x = scene.render.resolution_y = 700
    scene.display.shading.light = "FLAT"
    scene.display.shading.color_type = "TEXTURE"
    temp = []
    for name, file, loc, rot, width, aligned in REFERENCES:
        if not aligned:
            continue
        img = bpy.data.images.load(os.path.join(REF_DIR, file), check_existing=True)
        aspect = img.size[1] / img.size[0]
        bpy.ops.mesh.primitive_plane_add(size=1, location=loc)
        plane = bpy.context.active_object
        plane.scale = (width, width * aspect, 1)
        plane.rotation_euler = tuple(math.radians(a) for a in rot)
        mat = bpy.data.materials.new("ref")
        mat.use_nodes = True
        tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
        tex.image = img
        mat.node_tree.links.new(tex.outputs["Color"], mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"])
        plane.data.materials.append(mat)
        temp.append(plane)

    cams = {
        "top": ((0, 0, 12), (0, 0, 0)),
        "bottom": ((0, 0, -12), (180, 0, 180)),
        "front": ((0, -12, 0), (90, 0, 0)),
    }
    for view, (loc, rot) in cams.items():
        cam_data = bpy.data.cameras.new(view)
        cam_data.type = "ORTHO"
        cam_data.ortho_scale = 4.2
        cam = bpy.data.objects.new(view, cam_data)
        cam.location = loc
        cam.rotation_euler = tuple(math.radians(a) for a in rot)
        scene.collection.objects.link(cam)
        scene.camera = cam
        scene.render.filepath = os.path.join(out_dir, f"ref_{view}.png")
        bpy.ops.render.render(write_still=True)
        print(f"[reference] rendered {scene.render.filepath}")


if __name__ == "__main__":
    add_references()
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    if "--verify" in argv:
        out = argv[argv.index("--verify") + 1] if len(argv) > argv.index("--verify") + 1 else "/tmp"
        bpy.ops.wm.save_mainfile()
        verify(out)
    else:
        bpy.ops.wm.save_mainfile()
