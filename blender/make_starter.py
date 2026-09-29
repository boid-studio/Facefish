"""
Build a starter fish that follows the conventions in blender/README.md, so
sculpting can begin on a mesh the app already understands.

    /Applications/Blender.app/Contents/MacOS/Blender -b -P blender/make_starter.py

Writes blender/fish_starter.blend and public/models/fish_starter.glb. Test the
GLB in the app with ?model=./models/fish_starter.glb; rename it to fish.glb
when it should replace the procedural fish.

What it makes:
  Head   the body mesh, facing -Y (Blender's front), top +Z, with all 52 Face
         Cap shape keys and jawOpen / mouthPucker / smile / frown / cheekPuff
         roughed in. No modifiers: the glTF exporter drops shape keys when it
         applies them, so the mesh is dense enough on its own.
  EyeL   eye sphere on the fish's own left (+X), like Blender's .L convention
  EyeR   eye sphere on the fish's own right (-X)
  Tail   flat tail fin, gets the ambient sway
  FinL / FinR   pectoral fins (not driven, just there)
"""
import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
BLEND_PATH = os.path.join(HERE, "fish_starter.blend")
GLB_PATH = os.path.join(ROOT, "public", "models", "fish_starter.glb")

sys.path.insert(0, HERE)
from add_facecap_shapekeys import FACECAP_SHAPES  # noqa: E402
from add_references import add_references  # noqa: E402


def smoothstep(a, b, x):
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def material(name, color, roughness=0.55):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    return mat


def add_sphere(name, radius, location, scale, segments=48, rings=32):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, radius=radius, location=location)
    obj = bpy.context.active_object
    obj.name = name
    obj.data.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bpy.ops.object.shade_smooth()
    return obj


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)

    skin = material("FishSkin", (1.0, 0.45, 0.16))
    fin = material("FishFin", (1.0, 0.62, 0.3), 0.6)
    white = material("EyeWhite", (1.0, 1.0, 1.0), 0.3)

    # --- Head: the body. Faces -Y, top +Z. About 2 m nose to tail. -------------
    # Dense enough (about 9k triangles) that shape keys deform smoothly without
    # a Subdivision modifier, which the exporter cannot combine with shape keys.
    head = add_sphere("Head", 1.0, (0, 0, 0), (0.9, 1.2, 0.75), segments=80, rings=56)
    head.data.materials.append(skin)

    # All 52 shape keys, in Face Cap order, with Face Cap names.
    head.shape_key_add(name="Basis", from_mix=False)
    keys = {}
    for name in FACECAP_SHAPES:
        keys[name] = head.shape_key_add(name=name, from_mix=False)
        keys[name].value = 0.0

    basis = head.data.shape_keys.key_blocks["Basis"].data
    verts = [v.co.copy() for v in basis]

    # Rough sculpts so the pipeline can be seen working. Replace them.
    for i, co in enumerate(verts):
        x, y, z = co.x, co.y, co.z
        front = smoothstep(0.1, 1.0, -y)           # toward the nose (-Y)
        lower = smoothstep(0.05, -0.55, z)         # below the mouth line
        upper = smoothstep(-0.05, 0.45, z)
        side = smoothstep(0.2, 0.75, abs(x))
        # jawOpen: the lower front drops and swings back.
        k = keys["jawOpen"].data[i].co
        k.z -= 0.42 * front * lower
        k.y += 0.12 * front * lower
        # mouthPucker / mouthFunnel: lips pushed forward and gathered in.
        for name, amount in (("mouthPucker", 0.22), ("mouthFunnel", 0.16)):
            k = keys[name].data[i].co
            lip = front * smoothstep(0.35, -0.35, abs(z))
            k.y -= amount * lip
            k.x -= x * 0.25 * lip
        # Smile and frown: mouth corners up / down, per side.
        # _L is the fish's own left, +X when it faces -Y.
        for name, sgn, zsgn in (("mouthSmile_L", 1, 1), ("mouthSmile_R", -1, 1), ("mouthFrown_L", 1, -1), ("mouthFrown_R", -1, -1)):
            corner = front * side * smoothstep(0.3, 0.0, abs(z)) * (1.0 if math.copysign(1, x) == sgn else 0.0)
            k = keys[name].data[i].co
            k.z += 0.12 * zsgn * corner
            k.x += 0.05 * sgn * corner
        # cheekPuff: the mid-body swells sideways.
        k = keys["cheekPuff"].data[i].co
        puff = smoothstep(-0.3, 0.6, -y) * (1 - front * 0.5) * side
        k.x += x * 0.18 * puff
        # browInnerUp / browDown: the top front rises or lowers a touch.
        k = keys["browInnerUp"].data[i].co
        k.z += 0.08 * front * upper
        for name, sgn in (("browDown_L", 1), ("browDown_R", -1)):
            k = keys[name].data[i].co
            k.z -= 0.07 * front * upper * (1.0 if math.copysign(1, x) == sgn else 0.0)

    # --- Eyes: separate spheres so the app can aim them. -----------------------
    for name, sx in (("EyeL", 1), ("EyeR", -1)):
        eye = add_sphere(name, 0.2, (sx * 0.5, -0.78, 0.28), (1, 1, 1), 32, 24)
        eye.data.materials.append(white)
        bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=16, radius=0.09, location=(sx * 0.5, -0.78 - 0.16, 0.28))
        iris = bpy.context.active_object
        iris.name = name + "Iris"
        iris.data.materials.append(material(name + "Iris", (0.1, 0.35, 0.8), 0.4))
        bpy.ops.object.shade_smooth()
        iris.parent = eye
        iris.matrix_parent_inverse = eye.matrix_world.inverted()
        eye.parent = head
        eye.matrix_parent_inverse = head.matrix_world.inverted()

    # --- Tail and fins. --------------------------------------------------------
    bpy.ops.mesh.primitive_plane_add(size=1.0, location=(0, 1.35, 0))
    tail = bpy.context.active_object
    tail.name = "Tail"
    tail.rotation_euler = (0, math.radians(90), 0)
    tail.scale = (0.9, 0.55, 1)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    tail.data.materials.append(fin)
    tail.parent = head
    tail.matrix_parent_inverse = head.matrix_world.inverted()

    for name, sx in (("FinL", -1), ("FinR", 1)):
        bpy.ops.mesh.primitive_plane_add(size=1.0, location=(sx * 0.95, -0.1, -0.15))
        f = bpy.context.active_object
        f.name = name
        f.rotation_euler = (math.radians(-20), 0, math.radians(-sx * 25))
        f.scale = (0.5, 0.35, 1)
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        f.data.materials.append(fin)
        f.parent = head
        f.matrix_parent_inverse = head.matrix_world.inverted()

    bpy.ops.object.select_all(action="DESELECT")
    head.select_set(True)
    bpy.context.view_layer.objects.active = head

    add_references()

    os.makedirs(os.path.dirname(GLB_PATH), exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    bpy.ops.export_scene.gltf(
        filepath=GLB_PATH,
        export_format="GLB",
        export_apply=True,
        export_morph=True,
        export_morph_normal=False,
        export_animations=False,
        export_yup=True,
    )
    print(f"[starter] saved {BLEND_PATH}")
    print(f"[starter] exported {GLB_PATH} ({os.path.getsize(GLB_PATH) // 1024} kB)")


main()
