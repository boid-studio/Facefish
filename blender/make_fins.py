"""Generate the fish's fins as separate meshes: ribbed fans with scalloped edges.

    /Applications/Blender.app/Contents/MacOS/Blender -b blender/fish_starter9.blend -P blender/make_fins.py

Every fin is a ruled sheet between a root line on the body (found by ray casting onto the Head
mesh) and a tip line; ribs run from root to tip, the sheet is corrugated between them and the tip
line is scalloped so each rib ends in a point, like the artist's turnaround. Tweak FINS below and
re-run: the objects are replaced. rig_fish.py parents them to their bones.

World space: the fish faces -Y, up is +Z, its own left is +X. The material "FishFin" is
double-sided (a single sheet) and uses a small generated texture: u runs across the ribs (one
texture repeat per rib), v from root to tip.
"""
import math

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

head = bpy.data.objects["Head"]
for k in head.data.shape_keys.key_blocks:
    k.value = 0.0
dg = bpy.context.evaluated_depsgraph_get()
ev = head.evaluated_get(dg)
m = ev.to_mesh()
bvh = BVHTree.FromPolygons([ev.matrix_world @ v.co for v in m.vertices], [p.vertices[:] for p in m.polygons])
ev.to_mesh_clear()


def hit(origin, direction, dist=5.0):
    loc, _, _, _ = bvh.ray_cast(Vector(origin), Vector(direction).normalized(), dist)
    return loc


def surface_top(y):
    return hit((0, y, 3), (0, 0, -1))


def surface_bottom(y):
    return hit((0, y, -3), (0, 0, 1))


def rotate(v, axis, deg):
    return Matrix.Rotation(math.radians(deg), 3, Vector(axis)) @ Vector(v)


def smooth(a, b, x):
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def profile(points, t):
    """Piecewise-smooth lookup in [(t, value), ...]."""
    for (t0, v0), (t1, v1) in zip(points, points[1:]):
        if t <= t1:
            f = (t - t0) / max(1e-6, t1 - t0)
            f = f * f * (3 - 2 * f)
            return v0 + (v1 - v0) * f
    return points[-1][1]


# ------------------------------------------------------------------ fin definitions
# root(t) -> world point on the body, dir(t) -> rib direction, length(t), normal for corrugation
def dorsal():
    ys = (-0.22, 0.66)
    def root(t):
        y = ys[0] + (ys[1] - ys[0]) * t
        p = surface_top(y)
        return p - Vector((0, 0, 0.05)) if p else Vector((0, y, 0.3))
    def direction(t):
        return rotate((0, 0, 1), (1, 0, 0), -(22 + 50 * t ** 1.1))   # lean back, more towards the tail
    def length(t):
        return profile([(0, 0.46), (0.1, 0.62), (0.32, 0.66), (0.62, 0.5), (0.88, 0.28), (1, 0.14)], t)
    return dict(name="Fin_Dorsal", bone="Dorsal", root=root, dir=direction, length=length, normal=Vector((1, 0, 0)),
                ribs=12, scallop=0.07, corrugate=0.022, samples=(12 * 10, 12))


def tail():
    pivot = Vector((0, 1.02, -0.37))
    def root(t):
        a = -62 + 124 * t                                           # from down-back to up-back
        d = rotate((0, 1, 0), (1, 0, 0), a)
        return pivot + d * 0.12
    def direction(t):
        return rotate((0, 1, 0), (1, 0, 0), -62 + 124 * t)
    def length(t):
        lobes = 0.82 - 0.24 * math.exp(-((t - 0.5) / 0.16) ** 2)   # a notch in the middle
        return lobes * (0.94 + 0.12 * t)                            # the upper lobe a bit longer
    return dict(name="Fin_Tail", bone="Tail", root=root, dir=direction, length=length, normal=Vector((1, 0, 0)),
                ribs=12, scallop=0.07, corrugate=0.024, samples=(12 * 10, 12))


def pectoral(side):
    s = 1 if side == "L" else -1
    n = Vector((0.72 * s, -0.66, 0.2)).normalized()                  # the fan faces out-front, so it reads from front, side and back
    mean = Vector((0.6 * s, 0.62, -0.5)).normalized()
    mean = (mean - n * mean.dot(n)).normalized()
    spread_axis = n.cross(mean).normalized()
    base_c = hit((2.0 * s, -0.06, -0.58), (-s, 0, 0))
    base_c = (base_c or Vector((0.7 * s, -0.06, -0.58))) - Vector((0.04 * s, 0, 0))
    def root(t):
        return base_c + spread_axis * (t - 0.5) * 0.26
    def direction(t):
        return (Matrix.Rotation(math.radians(-48 + 96 * t), 3, n) @ mean).normalized()
    def length(t):
        return profile([(0, 0.46), (0.3, 0.66), (0.65, 0.7), (1, 0.52)], t)
    return dict(name=f"Fin_Pectoral.{side}", bone=f"Fin.{side}", root=root, dir=direction, length=length, normal=n,
                ribs=9, scallop=0.07, corrugate=0.02, samples=(9 * 10, 10))


def anal():
    ys = (0.42, 0.78)
    def root(t):
        y = ys[0] + (ys[1] - ys[0]) * t
        p = surface_bottom(y)
        return p + Vector((0, 0, 0.04)) if p else Vector((0, y, -1.1))
    def direction(t):
        return rotate((0, 0, -1), (1, 0, 0), -(35 + 30 * t))            # down and back
    def length(t):
        return profile([(0, 0.2), (0.4, 0.3), (1, 0.18)], t)
    return dict(name="Fin_Anal", bone="Anal", root=root, dir=direction, length=length, normal=Vector((1, 0, 0)),
                ribs=6, scallop=0.07, corrugate=0.016, samples=(6 * 10, 8))


FINS = [dorsal(), tail(), pectoral("L"), pectoral("R"), anal()]


# ------------------------------------------------------------------ texture + material
def fin_material():
    S = 256
    u = (np.arange(S) + 0.5) / S
    v = (np.arange(S) + 0.5) / S
    U, V = np.meshgrid(u, v)                                        # one rib per u repeat
    ridge = 0.5 + 0.5 * np.cos(2 * np.pi * U)                       # 1 on the rib, 0 in the groove

    def lin(c):
        return (np.array(c) / 255.0) ** 2.2

    root_col = lin((212, 76, 108))
    tip_col = lin((238, 124, 150))
    groove = lin((168, 46, 82))
    rim = lin((190, 58, 94))
    base = root_col[None, None, :] * (1 - V[..., None]) + tip_col[None, None, :] * V[..., None]
    col = base * (0.78 + 0.3 * ridge[..., None]) + groove[None, None, :] * 0.0
    g = np.clip((0.25 - ridge) / 0.25, 0, 1)[..., None] * 0.55
    col = col * (1 - g) + groove[None, None, :] * g
    edge = np.clip((V - 0.9) / 0.1, 0, 1)[..., None] * 0.6
    col = col * (1 - edge) + rim[None, None, :] * edge
    srgb = np.clip(col, 0, 1) ** (1 / 2.2)
    rgba = np.concatenate([srgb, np.ones((S, S, 1))], axis=2).astype(np.float32)
    img = bpy.data.images.get("Fish_Fin") or bpy.data.images.new("Fish_Fin", S, S)
    img.pixels.foreach_set(rgba.ravel())
    img.filepath_raw = bpy.path.abspath("//textures/fish_fin.png")
    img.file_format = "PNG"
    img.save()
    img.filepath = "//textures/fish_fin.png"
    img.source = "FILE"

    mat = bpy.data.materials.get("FishFin") or bpy.data.materials.new("FishFin")
    mat.use_nodes = True
    mat.use_backface_culling = False                                # exported as doubleSided
    nt = mat.node_tree
    nt.nodes.clear()
    uv = nt.nodes.new("ShaderNodeUVMap")
    uv.uv_map = "FinUV"
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = 0.3
    bsdf.inputs["Sheen Weight"].default_value = 0.3
    bsdf.inputs["Sheen Tint"].default_value = (1.0, 0.85, 0.9, 1.0)
    bsdf.inputs["Coat Weight"].default_value = 0.25
    bsdf.inputs["Coat Roughness"].default_value = 0.2
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(uv.outputs[0], tex.inputs[0])
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(bsdf.outputs[0], out.inputs[0])
    return mat


# ------------------------------------------------------------------ build
def build(spec, mat):
    old = bpy.data.objects.get(spec["name"])
    if old:
        bpy.data.objects.remove(old, do_unlink=True)
    na, nr = spec["samples"]
    ribs = spec["ribs"]
    normal = spec["normal"]
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("FinUV")
    grid = []
    for i in range(na + 1):
        t = i / na
        root = spec["root"](t)
        d = spec["dir"](t).normalized()
        c = math.cos(2 * math.pi * ribs * t)
        wave = math.copysign(abs(c) ** 0.6, c)                        # rounder ribs, narrower grooves
        L = spec["length"](t) * (1 - spec["scallop"] * 0.5 * (1 - wave))
        # keep the edge ends rounded
        L *= 0.35 + 0.65 * smooth(0.0, 0.06, t) * smooth(1.0, 0.94, t)
        row = []
        for j in range(nr + 1):
            s = j / nr
            p = root + d * (L * s)
            side = normal - d * normal.dot(d)
            p += side.normalized() * spec["corrugate"] * wave * (s ** 0.7) * (0.4 + 0.6 * smooth(0, 0.2, s))
            row.append((bm.verts.new(p), (t * ribs, s)))
        grid.append(row)
    for i in range(na):
        for j in range(nr):
            quad = [grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]]
            f = bm.faces.new([q[0] for q in quad])
            f.smooth = True
            for loop, (_, uvco) in zip(f.loops, quad):
                loop[uvl].uv = uvco
    me = bpy.data.meshes.new(spec["name"])
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    obj = bpy.data.objects.new(spec["name"], me)
    bpy.context.scene.collection.objects.link(obj)
    obj["fin_bone"] = spec["bone"]
    return obj


mat = fin_material()
made = [build(spec, mat).name for spec in FINS]
bpy.ops.wm.save_mainfile()
print("FINS", made)
