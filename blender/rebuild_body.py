"""Rebuild the fish body behind the face as clean rings, shaped like the artist's turnaround.

    /Applications/Blender.app/Contents/MacOS/Blender -b blender/fish_starter9.blend -P blender/rebuild_body.py

Keeps the front of the Head mesh (face, eyes, mouth, teeth, tongue, and every shape key), cuts it
along a closed loop just behind the eyes, deletes everything behind, and lofts a new body from
that loop: rings that blend from the cut shape onto an ellipsoid fitted to the reference, then taper
into a short, laterally flattened tail stalk that ends in a cap where the tail fin attaches.

Head-local coordinates: +x fish's left, +y up, +z front (the Head object is rotated 90 degrees on X).
The body is sized from the eyes: in the reference the eye radius is ~0.28 of the body radius.
"""
import math

import bmesh
import bpy
from mathutils import Vector

CUT_Z = 0.36                      # keep faces in front of this (plus the whole mouth)
CENTER = Vector((0.0, -0.43, -0.03))
RADII = Vector((0.78, 0.96, 0.98))  # width, height, length
RINGS_BODY = 11                   # rings from the cut to the back of the ball
STALK = [(0.20, 0.30, 0.08), (0.11, 0.21, 0.17), (0.07, 0.16, 0.24)]  # (rx, ry, extra length) per stalk ring
BLEND_RINGS = 2                   # rings over which the cut shape turns into the ellipsoid

head = bpy.data.objects["Head"]
me = head.data
kb = me.shape_keys.key_blocks
for k in kb:
    k.value = 0.0

bm = bmesh.new()
bm.from_mesh(me)
B = bm.verts.layers.shape["Basis"]
layers = [bm.verts.layers.shape[k.name] for k in kb]
part = bm.faces.layers.float.get("part")


def centre(f):
    return sum((v[B] for v in f.verts), Vector()) / len(f.verts)


FOREHEAD_Y = 0.24                 # the reference's eyes sit at the top of the head: squash the forehead above this
FOREHEAD_SQUASH = 0.75

# ---- 0. lower the forehead above the brows (every shape key gets the same offset)
for v in bm.verts:
    p = v[B]
    if p.y > FOREHEAD_Y and p.z > 0.0:
        dy = -(p.y - FOREHEAD_Y) * FOREHEAD_SQUASH
        for layer in layers:
            v[layer] = v[layer] + Vector((0, dy, 0))
        v.co = v[B]

# ---- 1. what to keep: faces in front of the cut and the whole mouth, connected to the nose
keep = {f for f in bm.faces if centre(f).z > CUT_Z or (part and f[part] > 0.5)}
nose = max(keep, key=lambda f: centre(f).z)
comp, stack = {nose}, [nose]
while stack:
    f = stack.pop()
    for e in f.edges:
        for g in e.link_faces:
            if g in keep and g not in comp:
                comp.add(g)
                stack.append(g)
# remnants of the old dorsal fin on the forehead: faces lying in the centre plane
remnant = {f for f in comp if all(abs(v[B].x) < 0.025 for v in f.verts) and abs(f.normal.x) > 0.6}
comp -= remnant
bmesh.ops.delete(bm, geom=[f for f in bm.faces if f not in comp], context="FACES")
bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")

# small holes the remnants leave on the forehead: weld across the centre line, then fill
edges = [e for e in bm.edges if e.is_boundary]
chains = {}
for e in edges:
    for v in e.verts:
        chains.setdefault(v, set()).add(e)


def loops_of(boundary_edges):
    adj = {}
    for e in boundary_edges:
        a, b = e.verts
        adj.setdefault(a, set()).add(b)
        adj.setdefault(b, set()).add(a)
    seen, out = set(), []
    for v in adj:
        if v in seen:
            continue
        comp_v, st = [], [v]
        seen.add(v)
        while st:
            u = st.pop()
            comp_v.append(u)
            for w in adj[u]:
                if w not in seen:
                    seen.add(w)
                    st.append(w)
        out.append(comp_v)
    return out


loops = loops_of([e for e in bm.edges if e.is_boundary])
cut = max(loops, key=lambda L: (sum(1 for v in L if v[B].z < CUT_Z + 0.12), len(L)))
eye_like = [L for L in loops if L is not cut and len(L) >= 8 and abs(sum(v[B].x for v in L) / len(L)) > 0.2]
small = [L for L in loops if L is not cut and L not in eye_like]
for L in small:
    ed = [e for e in bm.edges if e.is_boundary and e.verts[0] in L and e.verts[1] in L]
    bmesh.ops.holes_fill(bm, edges=ed, sides=0)

# ---- 2. order the cut loop into a ring
ring = [cut[0]]
prev = None
while True:
    cur = ring[-1]
    nxt = [e.other_vert(cur) for e in cur.link_edges if e.is_boundary and e.other_vert(cur) in cut and e.other_vert(cur) is not prev]
    nxt = [n for n in nxt if n is not ring[0] or len(ring) == len(cut)]
    if not nxt or nxt[0] is ring[0]:
        break
    prev = cur
    ring.append(nxt[0])
assert len(ring) == len(cut), f"cut loop is not a simple ring ({len(ring)} of {len(cut)})"
N = len(ring)


def ang(v):
    p = v[B]
    return math.atan2((p.y - CENTER.y) / RADII.y, p.x / RADII.x)


# walk the ring in increasing angle so the new faces get consistent winding
angles = [ang(v) for v in ring]
if sum(((angles[(i + 1) % N] - angles[i] + math.pi) % (2 * math.pi) - math.pi) for i in range(N)) < 0:
    ring.reverse()
    angles = [ang(v) for v in ring]
uniform0 = angles[0]
unwrapped = [angles[0]]
for a in angles[1:]:
    d = (a - unwrapped[-1] + math.pi) % (2 * math.pi) - math.pi
    unwrapped.append(unwrapped[-1] + d)
even = [uniform0 + 2 * math.pi * i / N for i in range(N)]


def ellipse_point(phi, z):
    t = max(-1.0, min(1.0, (z - CENTER.z) / RADII.z))
    s = math.sqrt(max(0.0, 1 - t * t))
    return Vector((RADII.x * s * math.cos(phi), CENTER.y + RADII.y * s * math.sin(phi), z))


def smooth(a, b, x):
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


# ---- 3. body rings: polar angle on the ellipsoid from the cut back to ~150 degrees
z_cut = sum(v[B].z for v in ring) / N
th0 = math.acos(max(-1.0, min(1.0, (z_cut - CENTER.z) / RADII.z)))
th1 = math.radians(158)
prev_ring = ring
new_verts_all = []
for k in range(1, RINGS_BODY + 1):
    th = th0 + (th1 - th0) * k / RINGS_BODY
    z = CENTER.z + RADII.z * math.cos(th)
    b = smooth(0.0, 1.0, k / BLEND_RINGS)
    cur = []
    for i, v in enumerate(ring):
        phi = unwrapped[i] + (even[i] - unwrapped[i]) * smooth(0.0, 1.0, k / (RINGS_BODY * 0.45))
        target = ellipse_point(phi, z)
        start = v[B] + Vector((0, 0, z - z_cut))       # the cut shape carried backwards
        p = start.lerp(target, b)
        nv = bm.verts.new(p)
        cur.append(nv)
    for i in range(N):
        a, b2 = prev_ring[i], prev_ring[(i + 1) % N]
        c, d = cur[(i + 1) % N], cur[i]
        bm.faces.new((a, b2, c, d))
    new_verts_all += cur
    prev_ring = cur

# ---- 4. tail stalk: flattened rings, then a cap
z_back = CENTER.z + RADII.z * math.cos(th1)
for (rx, ry, extra) in STALK:
    z = z_back - extra
    cur = []
    for i in range(N):
        phi = even[i]
        p = Vector((rx * math.cos(phi), CENTER.y + 0.06 + ry * math.sin(phi), z))
        cur.append(bm.verts.new(p))
    for i in range(N):
        bm.faces.new((prev_ring[i], prev_ring[(i + 1) % N], cur[(i + 1) % N], cur[i]))
    new_verts_all += cur
    prev_ring = cur
tip = bm.verts.new(Vector((0, CENTER.y + 0.06, z_back - STALK[-1][2] - 0.03)))
for i in range(N):
    bm.faces.new((prev_ring[i], prev_ring[(i + 1) % N], tip))
new_verts_all.append(tip)

# new vertices take their position in every shape key (the rear body is not part of the face shapes)
for v in new_verts_all:
    for layer in layers:
        v[layer] = v.co.copy()

# ---- 5. relax the seam: the cut ring and the first new rings
seam = set(ring) | set(new_verts_all[: N * 4])
for _ in range(10):
    upd = {}
    for v in seam:
        nb = [e.other_vert(v).co for e in v.link_edges]
        upd[v] = v.co.lerp(sum(nb, Vector()) / len(nb), 0.3)
    for v, q in upd.items():
        d = q - v.co
        for layer in layers:
            v[layer] = v[layer] + d
        v.co = q

for f in bm.faces:
    f.smooth = True
bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
bm.to_mesh(me)
open_edges = sum(1 for e in bm.edges if e.is_boundary)
bm.free()
me.update()
# new faces are body skin, not mouth
pa = me.attributes.get("part")
bpy.ops.wm.save_mainfile()
print("REBUILD", {"cut_ring": N, "new_verts": len(new_verts_all), "verts": len(me.vertices), "faces": len(me.polygons),
                  "open_edges": open_edges, "small_holes_filled": len(small), "remnant_faces": len(remnant)})
