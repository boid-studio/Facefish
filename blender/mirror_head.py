"""Make the Head's basis exactly mirror-symmetric across X = 0, keeping every shape key's movement.

Run in your open fish file (Scripting workspace -> Open -> Run Script), in Object Mode.
Each vertex is paired with its twin on the other side (by position, and by the mesh connections
for vertices that have drifted). KEEP chooses the result: "average" moves both to the average of the
two, so neither side's sculpting is thrown away; "-X" keeps the fish's own right side (Blender's .R
side, on the left of the screen in front view) and copies it onto the other; "+X" the opposite.
Vertices on the middle line go to X = 0 exactly. Every shape key gets
the same correction, so each expression moves exactly as before relative to the new basis.
Topology, UVs and the keys' own left/right differences are not touched.
"""
import bpy
import numpy as np
from mathutils import kdtree

HEAD = "Head"
KEEP = "average"     # "average", "-X" (keep the fish's own right) or "+X" (keep the fish's own left)
TOLERANCE = 1e-3     # twins closer than this (after mirroring) are matched by position
if "KEEP_SIDE" in globals():   # run with KEEP_SIDE predefined to choose without editing the file
    KEEP = KEEP_SIDE

head = bpy.data.objects[HEAD]
me = head.data
n = len(me.vertices)
keys = me.shape_keys.key_blocks if me.shape_keys else []


def get(k):
    a = np.empty(n * 3)
    k.data.foreach_get("co", a)
    return a.reshape(-1, 3)


B = get(keys[0]) if keys else np.array([v.co[:] for v in me.vertices])
nb = [set() for _ in range(n)]
for e in me.edges:
    a, b = e.vertices
    nb[a].add(b)
    nb[b].add(a)

kd = kdtree.KDTree(n)
for i, p in enumerate(B):
    kd.insert(p, i)
kd.balance()
twin = [-1] * n
for i, p in enumerate(B):
    _, j, d = kd.find((-p[0], p[1], p[2]))
    if d < TOLERANCE:
        twin[i] = j
for _ in range(50):                      # drifted vertices: the one twin the matched neighbours agree on
    changed = False
    for i in range(n):
        if twin[i] >= 0:
            continue
        cands = None
        for a in nb[i]:
            if twin[a] >= 0:
                cands = set(nb[twin[a]]) if cands is None else cands & nb[twin[a]]
        good = [c for c in (cands or ()) if twin[c] in (-1, i) and all(twin[a] < 0 or twin[a] in nb[c] for a in nb[i])]
        if len(good) == 1:
            twin[i] = good[0]
            changed = True
    if not changed:
        break
twin = np.array(twin)
if (twin < 0).any() or not (twin[twin] == np.arange(n)).all():
    raise SystemExit(f"the mesh isn't mirror-symmetric in its connections ({int((twin < 0).sum())} vertices without a twin)")

F = np.array([-1.0, 1.0, 1.0])
if KEEP == "average":
    S = (B + B[twin] * F) / 2
elif KEEP in ("-X", "+X"):
    sign = -1.0 if KEEP == "-X" else 1.0
    kept = B[:, 0] * sign > B[twin, 0] * sign      # of each pair, the twin further out on the kept side
    S = np.where(kept[:, None], B, B[twin] * F)
else:
    raise SystemExit(f'KEEP must be "average", "-X" or "+X", not {KEEP!r}')
S[twin == np.arange(n), 0] = 0.0
D = S - B
for k in keys[1:]:
    k.data.foreach_set("co", (get(k) + D).ravel())
if keys:
    keys[0].data.foreach_set("co", S.ravel())
me.vertices.foreach_set("co", S.ravel())
me.update()
moved = np.linalg.norm(D, axis=1)
print(f"MIRROR {HEAD} ({KEEP}): {int((moved > 1e-3).sum())} vertices moved more than 1 mm, at most {moved.max():.4f}")
result = {"moved_over_1mm": int((moved > 1e-3).sum()), "max_move": round(float(moved.max()), 4)}
