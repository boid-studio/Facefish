"""Make one side's shape keys from the other side's: e.g. browDownLeft as the mirror image of browDownRight.

Run in your open fish file (Scripting workspace -> Open -> Run Script), in Object Mode. Edit PAIRS
(source -> target) or predefine PAIRS when running it from elsewhere. Each vertex is paired with its
twin across X = 0 (by position, and by the mesh connections for vertices that have drifted), and the
target key gets the source key's movement, mirrored. The target key is created if it's missing and
overwritten if it exists; the source key and everything else are untouched.
"""
import bpy
import numpy as np
from mathutils import kdtree

HEAD = "Head"
if "PAIRS" not in globals():
    PAIRS = {"browDownRight": "browDownLeft", "browOuterUpRight": "browOuterUpLeft"}
TOLERANCE = 1e-3

head = bpy.data.objects[HEAD]
me = head.data
kb = me.shape_keys.key_blocks
n = len(me.vertices)


def get(k):
    a = np.empty(n * 3)
    k.data.foreach_get("co", a)
    return a.reshape(-1, 3)


B = get(kb[0])
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
    raise RuntimeError(f"the mesh isn't mirror-symmetric in its connections ({int((twin < 0).sum())} vertices without a twin)")

F = np.array([-1.0, 1.0, 1.0])
made = []
for src, dst in PAIRS.items():
    if src not in kb:
        import difflib
        close = difflib.get_close_matches(src, [k.name for k in kb], n=3)
        raise RuntimeError(f"no shape key {src!r}" + (f"; did you mean {', '.join(close)}?" if close else ""))
    D = (get(kb[src]) - B)[twin] * F          # the twin's movement, mirrored
    key = kb.get(dst)
    if key is None:
        key = head.shape_key_add(name=dst, from_mix=False)
        key.value = 0.0
    key.relative_key = kb[0]
    key.slider_min, key.slider_max = kb[src].slider_min, kb[src].slider_max
    key.data.foreach_set("co", (B + D).ravel())
    made.append((src, dst, int((np.linalg.norm(D, axis=1) > 1e-4).sum())))
me.update()
print("MIRRORED", made)
result = {"made": made}
