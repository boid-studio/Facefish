"""Bake all fins into one texture, fins_bake, in a single bake.

Open your fish in Blender, then: Scripting workspace -> Open -> blender/bake_fins.py -> Run Script.
(Or headless: Blender -b blender/<fish>.blend -P blender/bake_fins.py, which saves the file.)

Why: with "Clear Image" on, every bake wipes the image first, so baking fins one by one keeps only
the last one. This bakes every visible Fin_* mesh at once, with your current bake settings (bake
type, passes, margin) from Properties -> Render -> Bake.

- all fins bake into the image "fins_bake" (each fin material gets an image node for it if it has
  none, made the active node; nothing is connected or rewired)
- the fins must not overlap in their texture UV map (FinUV); the two pectoral fins share texels
  on purpose (mirror copies)
- the FinWave preview ripple is switched off during the bake so the fins bake at rest, then back on
- the previous image is kept in the file as "fins_bake (previous)" (delete it when you're happy),
  and the result is packed into the .blend
Your selection and active object are restored afterwards.
"""
import bpy

IMAGE = "fins_bake"

img = bpy.data.images.get(IMAGE)
if img is None:
    raise SystemExit(f"No image called {IMAGE!r}. Create it in the Image Editor first (e.g. 2048 x 2048).")
fins = [o for o in bpy.context.view_layer.objects if o.type == "MESH" and o.name.startswith("Fin_") and o.visible_get()]
if not fins:
    raise SystemExit("No visible Fin_* meshes.")

if bpy.context.mode != "OBJECT":
    bpy.ops.object.mode_set(mode="OBJECT")

# keep the previous result, in case the new bake isn't what you wanted
old = bpy.data.images.get(IMAGE + " (previous)")
if old is not None:
    bpy.data.images.remove(old)
backup = img.copy()
backup.name = IMAGE + " (previous)"
backup.pack()
backup.use_fake_user = True          # kept in the .blend; delete it when you're happy with the new bake

# every fin material: an image node with fins_bake, made active (the bake target)
for o in fins:
    for slot in o.material_slots:
        m = slot.material
        if m is None or not m.use_nodes:
            continue
        nt = m.node_tree
        node = next((n for n in nt.nodes if n.type == "TEX_IMAGE" and n.image == img), None)
        if node is None:
            node = nt.nodes.new("ShaderNodeTexImage")
            node.image = img
            node.name = node.label = "fins_bake (bake target)"
            node.location = (-600, -400)
        nt.nodes.active = node

# fins at rest: ripple preview off for the bake
previews = [(o, m) for o in fins for m in o.modifiers if m.name.startswith("FinWave preview") and m.show_viewport]
for _, m in previews:
    m.show_viewport = False
    m.show_render = False

view_layer = bpy.context.view_layer
selected = [o for o in view_layer.objects if o.select_get()]
active = view_layer.objects.active
for o in selected:
    o.select_set(False)
for o in fins:
    o.select_set(True)
view_layer.objects.active = fins[0]

scene = bpy.context.scene
bake_type = scene.cycles.bake_type if scene.render.engine == "CYCLES" else "DIFFUSE"
if scene.render.engine != "CYCLES":
    print("[bake] switching to Cycles for the bake")
    engine = scene.render.engine
    scene.render.engine = "CYCLES"
else:
    engine = None
try:
    bpy.ops.object.bake(type=bake_type)
finally:
    for _, m in previews:
        m.show_viewport = True
        m.show_render = True
    for o in fins:
        o.select_set(False)
    for o in selected:
        o.select_set(True)
    view_layer.objects.active = active
    if engine:
        scene.render.engine = engine

img.pack()
if bpy.app.background:
    bpy.ops.wm.save_mainfile()
print(f"[bake] {bake_type} of {', '.join(o.name for o in fins)} into {IMAGE} ({img.size[0]}x{img.size[1]}); "
      f"previous image kept as {backup.name!r}")
