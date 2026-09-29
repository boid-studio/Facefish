"""Bake the fish skin (AO, colour, normal) and build three.js-safe materials.

    /Applications/Blender.app/Contents/MacOS/Blender -b blender/fish_starter8.blend -P blender/bake_fish_skin.py [-- AO_SAMPLES]

Re-run after sculpting: the look comes from a procedural source material, baked to images, and
the exported material is only a Principled BSDF with those images, which glTF and three.js read.
It needs what fish_starter7 already has on the Head mesh: the "Bake" UV layer and the attributes
fin, fin_r, fin_edge, fan_c, fan_md, fan_side, fan_k (fins and ribs) and part (1 mouth, 2 teeth,
3 tongue). Keep the vertex count the same when sculpting and those stay valid.

Source material  : FishSkin_Source  (procedural, kept with a fake user for re-baking)
Export material  : FishBody         (Principled BSDF + base colour image + normal map)
Eyes             : FishEye          (Principled BSDF + generated iris image, front-projected UVs)
"""
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
COLOR_W, COLOR_H = 4096, 2048
NORMAL_W, NORMAL_H = 2048, 1024
AO_SAMPLES = int(ARGS[0]) if ARGS else 128

scene = bpy.context.scene
head = bpy.data.objects["Head"]
me = head.data
eyes = [bpy.data.objects["Eye.L"], bpy.data.objects["Eye.R"]]
tex_dir = bpy.path.abspath("//textures")
os.makedirs(tex_dir, exist_ok=True)
me.shape_keys.key_blocks["jawOpen"].value = 0.0

# ---------------------------------------------------------------- render setup
scene.render.engine = "CYCLES"
try:
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "METAL"
    prefs.get_devices()
    for d in prefs.devices:
        d.use = True
    scene.cycles.device = "GPU"
except Exception:
    scene.cycles.device = "CPU"

# only the fish takes part in the bake
render_state = {o.name: o.hide_render for o in bpy.data.objects}
for o in bpy.data.objects:
    o.hide_render = o not in (head, *eyes)


def image(name, w, h, non_color=False, fill=(0, 0, 0, 1)):
    img = bpy.data.images.get(name)
    if img and (img.size[0] != w or img.size[1] != h):
        bpy.data.images.remove(img)
        img = None
    if img is None:
        img = bpy.data.images.new(name, w, h, alpha=False, float_buffer=False)
    img.colorspace_settings.name = "Non-Color" if non_color else "sRGB"
    img.generated_color = fill
    return img


def save(img, filename):
    img.filepath_raw = os.path.join(tex_dir, filename)
    img.file_format = "PNG"
    img.save()
    img.filepath = "//textures/" + filename
    img.source = "FILE"


def select_only(obj):
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


class Nodes:
    def __init__(self, mat):
        self.nt = mat.node_tree
        self.nt.nodes.clear()
        self.x = 0

    def n(self, kind, **kw):
        node = self.nt.nodes.new(kind)
        node.location = (self.x, 0)
        self.x += 40
        for k, v in kw.items():
            if k.startswith("in_"):
                key = k[3:]
                key = int(key) if key.isdigit() else key.replace("__", " ")
                node.inputs[key].default_value = v
            else:
                setattr(node, k, v)
        return node

    def link(self, a, b, ai=0, bi=0):
        self.nt.links.new(a.outputs[ai] if isinstance(ai, (int, str)) else ai, b.inputs[bi])

    def math(self, op, a, b=None, clamp=False):
        m = self.n("ShaderNodeMath", operation=op, use_clamp=clamp)
        for i, v in enumerate((a, b)):
            if v is None:
                continue
            if isinstance(v, (int, float)):
                m.inputs[i].default_value = v
            else:
                self.nt.links.new(v, m.inputs[i])
        return m.outputs[0]

    def smooth(self, x, lo, hi):
        r = self.n("ShaderNodeMapRange", interpolation_type="SMOOTHSTEP", clamp=True)
        self.nt.links.new(x, r.inputs["Value"])
        r.inputs["From Min"].default_value = lo
        r.inputs["From Max"].default_value = hi
        return r.outputs["Result"]

    def mix(self, fac, a, b):
        m = self.n("ShaderNodeMix", data_type="RGBA", blend_type="MIX", clamp_factor=True)
        for sock, v in ((m.inputs[0], fac), (m.inputs[6], a), (m.inputs[7], b)):
            if isinstance(v, (tuple, list)):
                sock.default_value = (*v, 1.0) if len(v) == 3 else v
            elif isinstance(v, (int, float)):
                sock.default_value = v
            else:
                self.nt.links.new(v, sock)
        return m.outputs[2]

    def attr(self, name, kind="GEOMETRY"):
        a = self.n("ShaderNodeAttribute", attribute_name=name, attribute_type=kind)
        return a.outputs["Fac"]


def srgb(r, g, b):
    def c(v):
        v /= 255.0
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    return (c(r), c(g), c(b))


# palette (from the reference photos)
BODY = srgb(243, 140, 186)
DISC = srgb(250, 188, 212)
DISC_RIM = srgb(170, 60, 118)
FRECKLE = srgb(180, 50, 120)
FIN_LIGHT = srgb(244, 239, 245)
FIN_RIB = srgb(196, 186, 206)
FIN_RIM = srgb(74, 100, 110)
MOUTH = srgb(118, 22, 52)
TEETH = srgb(246, 243, 232)
TONGUE = srgb(240, 118, 150)
TONGUE_GROOVE = srgb(196, 70, 108)
AO_TINT = srgb(150, 40, 105)


def surface_points(spots):
    from mathutils.bvhtree import BVHTree
    dg = bpy.context.evaluated_depsgraph_get()
    ev = head.evaluated_get(dg)
    m = ev.to_mesh()
    bvh = BVHTree.FromPolygons([v.co.copy() for v in m.vertices], [p.vertices[:] for p in m.polygons])
    ev.to_mesh_clear()
    out = []
    for (x, y, r) in spots:
        hit, _, _, _ = bvh.ray_cast(Vector((x, y, 3.0)), Vector((0, 0, -1)), 6.0)
        if hit is not None:
            out.append((hit.x, hit.y, hit.z, r))
    return out


FRECKLES = []


def build_source(ao_img):
    mat = bpy.data.materials.get("FishSkin_Source") or bpy.data.materials.new("FishSkin_Source")
    mat.use_nodes = True
    mat.use_fake_user = True
    N = Nodes(mat)
    tc = N.n("ShaderNodeTexCoord")
    sep = N.n("ShaderNodeSeparateXYZ")
    N.link(tc, sep, "Object", 0)
    X, Y, Z = sep.outputs[0], sep.outputs[1], sep.outputs[2]
    ax = N.math("ABSOLUTE", X)
    fin = N.attr("fin")
    rib = N.attr("fin_rib")
    fr = N.attr("fin_r")
    fe = N.attr("fin_edge")
    part = N.attr("part")

    # --- scale discs: 2D voronoi on a sphere around the body, so every patch of skin gets discs
    cx, cy, cz = 0.0, -0.1, -0.05
    Yc = N.math("SUBTRACT", Y, cy)
    Zc = N.math("SUBTRACT", Z, cz)
    az = N.math("ARCTAN2", X, N.math("MULTIPLY", Zc, -1.0))          # 0 at the tail, wraps at the face
    horiz = N.math("SQRT", N.math("ADD", N.math("MULTIPLY", X, X), N.math("MULTIPLY", Zc, Zc)))
    el = N.math("ARCTAN2", Yc, horiz)
    comb = N.n("ShaderNodeCombineXYZ")
    N.nt.links.new(N.math("MULTIPLY", az, 0.9), comb.inputs[0])
    N.nt.links.new(N.math("MULTIPLY", el, 0.9), comb.inputs[1])
    vor = N.n("ShaderNodeTexVoronoi", voronoi_dimensions="2D", feature="F1", distance="EUCLIDEAN")
    vor.inputs["Scale"].default_value = 2.5
    vor.inputs["Randomness"].default_value = 0.75
    N.link(comb, vor, 0, "Vector")
    d = vor.outputs["Distance"]
    rnd = N.n("ShaderNodeSeparateColor")
    N.link(vor, rnd, "Color", 0)
    radius = N.math("MULTIPLY_ADD", rnd.outputs[0], 0.12)
    radius.node.inputs[2].default_value = 0.30
    inner = N.math("SUBTRACT", radius, 0.05)
    disc = N.math("SUBTRACT", 1.0, N.smooth(N.math("SUBTRACT", d, inner), -0.006, 0.014))
    rim_out = N.math("SUBTRACT", 1.0, N.smooth(N.math("SUBTRACT", d, radius), -0.008, 0.010))
    rim = N.math("SUBTRACT", rim_out, disc, clamp=True)
    behind_face = N.math("SUBTRACT", 1.0, N.smooth(Z, 0.30, 0.52))
    is_body = N.math("SUBTRACT", 1.0, N.smooth(fin, 0.05, 0.6))
    not_mouth = N.math("LESS_THAN", part, 0.5)
    zone = N.math("MULTIPLY", N.math("MULTIPLY", behind_face, is_body), not_mouth)
    disc_z = N.math("MULTIPLY", disc, zone)
    rim_z = N.math("MULTIPLY", rim, zone)
    col = N.mix(disc_z, BODY, DISC)
    col = N.mix(N.math("MULTIPLY", rim_z, 1.0), col, DISC_RIM)

    # --- freckles, placed by hand like the photo (big one between the eyes, three small ones)
    freck = None
    for (px, py, pz, pr) in FRECKLES:
        dist = N.n("ShaderNodeVectorMath", operation="DISTANCE")
        N.link(tc, dist, "Object", 0)
        dist.inputs[1].default_value = (px, py, pz)
        dot = N.math("SUBTRACT", 1.0, N.smooth(dist.outputs["Value"], pr * 0.75, pr))
        freck = dot if freck is None else N.math("MAXIMUM", freck, dot)
    col = N.mix(N.math("MULTIPLY", freck, is_body), col, FRECKLE)

    # --- fins: straight radial ribs from each fin's fan centre, pink root, dark outer rim
    fc = N.n("ShaderNodeAttribute", attribute_name="fan_c", attribute_type="GEOMETRY")
    fmd = N.n("ShaderNodeAttribute", attribute_name="fan_md", attribute_type="GEOMETRY")
    fsd = N.n("ShaderNodeAttribute", attribute_name="fan_side", attribute_type="GEOMETRY")
    fk = N.attr("fan_k")
    dv = N.n("ShaderNodeVectorMath", operation="SUBTRACT")
    N.link(tc, dv, "Object", 0)
    N.nt.links.new(fc.outputs["Vector"], dv.inputs[1])
    da = N.n("ShaderNodeVectorMath", operation="DOT_PRODUCT")
    N.nt.links.new(dv.outputs[0], da.inputs[0])
    N.nt.links.new(fsd.outputs["Vector"], da.inputs[1])
    db = N.n("ShaderNodeVectorMath", operation="DOT_PRODUCT")
    N.nt.links.new(dv.outputs[0], db.inputs[0])
    N.nt.links.new(fmd.outputs["Vector"], db.inputs[1])
    ang = N.math("ARCTAN2", da.outputs["Value"], db.outputs["Value"])
    ribwave = N.math("MULTIPLY_ADD", N.math("COSINE", N.math("MULTIPLY", ang, fk)), 0.5)
    ribwave.node.inputs[2].default_value = 0.5
    ribs = N.smooth(ribwave, 0.15, 0.75)
    fin_col = N.mix(ribs, FIN_RIB, FIN_LIGHT)
    fin_col = N.mix(N.math("SUBTRACT", 1.0, N.smooth(fr, 0.0, 0.3)), fin_col, BODY)
    rim_f = N.math("MULTIPLY", N.smooth(fe, 0.45, 0.9), N.smooth(fr, 0.25, 0.55))
    fin_col = N.mix(N.math("MULTIPLY", rim_f, 0.85), fin_col, FIN_RIM)
    col = N.mix(N.smooth(fin, 0.1, 0.8), col, fin_col)

    # --- mouth: interior, teeth, tongue (face attribute "part": 1 mouth, 2 teeth, 3 tongue)
    groove = N.math("SUBTRACT", 1.0, N.smooth(ax, 0.0, 0.035))
    tongue_col = N.mix(N.math("MULTIPLY", groove, 0.8), TONGUE, TONGUE_GROOVE)
    is_mouth = N.math("MULTIPLY", N.math("GREATER_THAN", part, 0.5), N.math("LESS_THAN", part, 1.5))
    is_teeth = N.math("MULTIPLY", N.math("GREATER_THAN", part, 1.5), N.math("LESS_THAN", part, 2.5))
    is_tongue = N.math("GREATER_THAN", part, 2.5)
    col = N.mix(is_mouth, col, MOUTH)
    col = N.mix(is_teeth, col, TEETH)
    col = N.mix(is_tongue, col, tongue_col)

    # --- ambient occlusion from the AO bake, tinted magenta like the photo's crevices
    uv = N.n("ShaderNodeUVMap", uv_map="Bake")
    ao = N.n("ShaderNodeTexImage", image=ao_img, interpolation="Linear")
    N.link(uv, ao, 0, 0)
    occl = N.math("SUBTRACT", 1.0, ao.outputs["Color"])
    tint = N.mix(N.math("MULTIPLY", occl, 0.9), (1.0, 1.0, 1.0), AO_TINT)
    shaded = N.n("ShaderNodeMix", data_type="RGBA", blend_type="MULTIPLY", clamp_factor=True)
    shaded.inputs[0].default_value = 1.0
    N.nt.links.new(col, shaded.inputs[6])
    N.nt.links.new(tint, shaded.inputs[7])
    col = shaded.outputs[2]

    # --- height for the normal map: raised discs, fin ribs, tongue groove
    h = N.math("ADD", N.math("MULTIPLY", disc_z, 1.0), N.math("MULTIPLY", N.math("MULTIPLY", ribwave, fin), 0.9))
    h = N.math("SUBTRACT", h, N.math("MULTIPLY", N.math("MULTIPLY", groove, is_tongue), 0.6))
    bump = N.n("ShaderNodeBump", in_Strength=1.0, in_Distance=0.012)
    N.nt.links.new(h, bump.inputs["Height"])

    bsdf = N.n("ShaderNodeBsdfPrincipled")
    N.nt.links.new(col, bsdf.inputs["Base Color"])
    N.nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
    bsdf.inputs["Roughness"].default_value = 0.5
    out = N.n("ShaderNodeOutputMaterial")
    N.link(bsdf, out, 0, 0)
    target = N.n("ShaderNodeTexImage")
    return mat, target


def bake_into(obj, mat, target_node, img, bake_type, samples=1, margin=16):
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    target_node.image = img
    mat.node_tree.nodes.active = target_node
    scene.cycles.samples = samples
    scene.render.bake.margin = margin
    scene.render.bake.use_clear = True
    scene.render.bake.target = "IMAGE_TEXTURES"
    if bake_type == "DIFFUSE":
        scene.render.bake.use_pass_direct = False
        scene.render.bake.use_pass_indirect = False
        scene.render.bake.use_pass_color = True
    if bake_type == "NORMAL":
        scene.render.bake.normal_space = "TANGENT"
    select_only(obj)
    bpy.ops.object.bake(type=bake_type, uv_layer="Bake")


# 1) AO
ao_img = image("Fish_AO", NORMAL_W, NORMAL_H, non_color=True, fill=(1, 1, 1, 1))
ao_mat = bpy.data.materials.get("_bake_ao") or bpy.data.materials.new("_bake_ao")
ao_mat.use_nodes = True
ao_target = ao_mat.node_tree.nodes.get("target") or ao_mat.node_tree.nodes.new("ShaderNodeTexImage")
ao_target.name = "target"
if scene.world is None:
    scene.world = bpy.data.worlds.new("World")
scene.world.light_settings.distance = 0.35
bake_into(head, ao_mat, ao_target, ao_img, "AO", samples=AO_SAMPLES)
save(ao_img, "fish_ao.png")

# 2) colour and normal from the procedural source
FRECKLES[:] = surface_points([(-0.08, -0.05, 0.05), (0.012, 0.24, 0.024), (-0.055, -0.15, 0.022), (0.10, -0.11, 0.022)])
print('FRECKLES', [[round(c, 2) for c in f] for f in FRECKLES])
src, target = build_source(ao_img)
color_img = image("Fish_BaseColor", COLOR_W, COLOR_H)
bake_into(head, src, target, color_img, "DIFFUSE", samples=1)
save(color_img, "fish_basecolor.png")
normal_img = image("Fish_Normal", NORMAL_W, NORMAL_H, non_color=True, fill=(0.5, 0.5, 1, 1))
bake_into(head, src, target, normal_img, "NORMAL", samples=4)
save(normal_img, "fish_normal.png")

# 3) export material
skin = bpy.data.materials.get("FishBody") or bpy.data.materials.new("FishBody")
skin.use_nodes = True
N = Nodes(skin)
uv = N.n("ShaderNodeUVMap", uv_map="Bake")
base = N.n("ShaderNodeTexImage", image=color_img)
nrm = N.n("ShaderNodeTexImage", image=normal_img)
N.link(uv, base, 0, 0)
N.link(uv, nrm, 0, 0)
nmap = N.n("ShaderNodeNormalMap", uv_map="Bake", space="TANGENT")
N.link(nrm, nmap, "Color", "Color")
bsdf = N.n("ShaderNodeBsdfPrincipled")
bsdf.inputs["Roughness"].default_value = 0.5
N.link(base, bsdf, "Color", "Base Color")
N.link(nmap, bsdf, "Normal", "Normal")
out = N.n("ShaderNodeOutputMaterial")
N.link(bsdf, out, 0, 0)
head.data.materials.clear()
head.data.materials.append(skin)

# ---------------------------------------------------------------- eyes
S = 1024
yy, xx = np.mgrid[0:S, 0:S]
u = (xx + 0.5) / S
v = (yy + 0.5) / S
iris_c = (0.47, 0.51)                      # a touch inward (towards the nose), like the photo
r = np.hypot(u - iris_c[0], v - iris_c[1])
ang = np.arctan2(v - iris_c[1], u - iris_c[0])


def lin(c):
    return np.array(srgb(*c))


sclera = lin((250, 248, 246))
iris_out = lin((34, 18, 12))
iris_in = lin((92, 52, 28))
pupil = lin((8, 6, 6))
R_IRIS, R_PUPIL = 0.22, 0.13


def sstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


streak = 0.5 + 0.5 * np.cos(ang * 38 + 3 * np.sin(ang * 7))
t = np.clip((r - R_PUPIL) / (R_IRIS - R_PUPIL), 0, 1)
iris_col = iris_in[None, None, :] * (1 - t[..., None]) + iris_out[None, None, :] * t[..., None]
iris_col *= (0.82 + 0.18 * streak)[..., None]
col = np.broadcast_to(sclera, (S, S, 3)).copy()
# soft shadow ring on the white near the rim of the visible eye
col *= (1 - 0.18 * sstep(0.36, 0.5, np.hypot(u - 0.5, v - 0.5)))[..., None]
iris_m = 1 - sstep(R_IRIS - 0.006, R_IRIS + 0.004, r)
col = col * (1 - iris_m[..., None]) + iris_col * iris_m[..., None]
limbal = sstep(R_IRIS - 0.03, R_IRIS - 0.004, r) * iris_m
col *= (1 - 0.55 * limbal)[..., None]
pupil_m = 1 - sstep(R_PUPIL - 0.004, R_PUPIL + 0.004, r)
col = col * (1 - pupil_m[..., None]) + pupil[None, None, :] * pupil_m[..., None]
# catch-light, upper left of the pupil
hl = 1 - sstep(0.018, 0.026, np.hypot(u - (iris_c[0] - 0.06), v - (iris_c[1] + 0.07)))
col = col * (1 - hl[..., None]) + np.array([1.0, 1.0, 1.0]) * hl[..., None]
# linear -> sRGB for an 8-bit sRGB image
srgb_col = np.where(col <= 0.0031308, col * 12.92, 1.055 * np.power(np.clip(col, 0, 1), 1 / 2.4) - 0.055)
rgba = np.concatenate([srgb_col, np.ones((S, S, 1))], axis=2).astype(np.float32)
eye_img = image("Fish_Eye", S, S)
eye_img.pixels.foreach_set(rgba.ravel())
save(eye_img, "fish_eye.png")

eye_mat = bpy.data.materials.get("FishEye") or bpy.data.materials.new("FishEye")
eye_mat.use_nodes = True
N = Nodes(eye_mat)
uv = N.n("ShaderNodeUVMap", uv_map="EyeFront")
tex = N.n("ShaderNodeTexImage", image=eye_img)
N.link(uv, tex, 0, 0)
bsdf = N.n("ShaderNodeBsdfPrincipled")
bsdf.inputs["Roughness"].default_value = 0.12
bsdf.inputs["Coat Weight"].default_value = 0.6
bsdf.inputs["Coat Roughness"].default_value = 0.04
N.link(tex, bsdf, "Color", "Base Color")
out = N.n("ShaderNodeOutputMaterial")
N.link(bsdf, out, 0, 0)

eye_report = {}
world_fwd, world_up = Vector((0, -1, 0)), Vector((0, 0, 1))
for eye in eyes:
    em = eye.data
    inv = eye.matrix_world.to_3x3().inverted()
    fwd = (inv @ world_fwd).normalized()
    up = inv @ world_up
    up = (up - fwd * up.dot(fwd)).normalized()
    right = up.cross(fwd).normalized()          # screen right when looking at the fish's face
    xs = [v.co for v in em.vertices]
    center = sum(xs, Vector()) / len(xs)
    radius = max((p - center).length for p in xs)
    mirror = eye.name.endswith(".R")            # same image, mirrored, so both irises sit towards the nose
    bm = bmesh.new()
    bm.from_mesh(em)
    uvl = bm.loops.layers.uv.get("EyeFront") or bm.loops.layers.uv.new("EyeFront")
    for f in bm.faces:
        for l in f.loops:
            p = l.vert.co - center
            uu = 0.5 + p.dot(right) / (2 * radius)
            vv = 0.5 + p.dot(up) / (2 * radius)
            l[uvl].uv = (1 - uu if mirror else uu, vv)
    bm.to_mesh(em)
    bm.free()
    em.uv_layers["EyeFront"].active_render = True
    em.materials.clear()
    em.materials.append(eye_mat)
    for p in em.polygons:
        p.material_index = 0
    eye_report[eye.name] = {"radius": round(radius, 3), "fwd_local": [round(c, 2) for c in fwd]}

for name, hidden in render_state.items():
    if name in bpy.data.objects:
        bpy.data.objects[name].hide_render = hidden
scene.render.engine = "BLENDER_EEVEE"
bpy.ops.wm.save_mainfile()
print("STEPB", {"eyes": eye_report, "device": scene.cycles.device})
