# Building the fish in Blender

The app loads `public/models/fish.glb` if it exists (or `?model=<url>` for
testing) and falls back to the procedural fish otherwise. Everything below is
about making that file so the tracking data lands on the right parts.

## Getting started

There is a starter file that already follows every convention below:

```sh
/Applications/Blender.app/Contents/MacOS/Blender -b -P blender/make_starter.py
```

writes `blender/fish_starter.blend` and exports `public/models/fish_starter.glb`.
Open the `.blend` in Blender and you have a `Head` mesh facing the right way with
all 52 shape keys, a handful roughed in (`jawOpen`, `mouthPucker`, smile, frown,
`cheekPuff`, brows), separate `EyeL` / `EyeR` spheres and a `Tail`. Test it in
the app with `?model=./models/fish_starter.glb`; when it should replace the
procedural fish, export to `public/models/fish.glb`.

Four reference drawings are in the file as image empties, in the `Reference`
collection: top, bottom and front each show only in their own orthographic view
(numpad 7, ctrl+numpad 7, numpad 1), behind the model at half opacity, and a
three-quarter view stands as a board beside the model. Replace the files in
`blender/reference/` and re-run `blender/add_references.py` to swap them.

The workflow from there:

1. **Shape the body first**, in Sculpt or Edit mode on the Basis key with all
   other keys at 0. Shape keys store offsets, so the rough sculpts survive body
   edits, but adding or deleting vertices does not: settle the topology before
   sculpting expressions.
2. **Sculpt the expressions** one key at a time: select the key in Object Data →
   Shape Keys, set its value to 1, sculpt, set it back to 0. `jawOpen` first.
3. **Export** by saving the file and running

   ```sh
   /Applications/Blender.app/Contents/MacOS/Blender -b blender/<your file>.blend -P blender/export_fish.py
   ```

   which writes `public/models/fish.glb` (add `-- fish_test.glb` for another
   name, then open the app with `?model=./models/fish_test.glb`). Only visible
   objects are exported. The script bakes Mirror, Subdivision and other
   modifiers into the shape keys, which Blender's own exporter cannot do. Then
   watch the browser console: the app lists matched shape keys, nodes and the
   triangle count. The manual settings are under *Export* below.

## The expressive fish (fish_starter10)

`fish_starter10.blend` is fish_starter9 sculpted towards the artist's expression sheets in
`reference/expressions/` (sing, neutral, surprised, sad, laugh). It is what
`public/models/fish.glb` holds now. On top of the fish_starter9 steps below, these scripts ran on
the Head mesh only (no new objects):

1. `sculpt_round.py`: rounder, egg-shaped ball; eyes scaled with their sockets; lips forward.
2. `sculpt_face.py`: eyes spread further round the ball; the mouth closed at rest; fuller lips.
3. `sculpt_eyelids.py`: slightly smaller eyeballs sunk a little into the sockets, and lids that
   slide over the top and bottom of each eyeball, so the eyes are lidded like the reference.
4. `sculpt_mouth.py`: a narrower mouth (corners in along the curve of the head, a little up into a
   smile) and relaxed, rounder lips.

Then the usual steps 3 to 7 below: face shapes, bake, rig, swim, export.

**Eyelids.** The head is open behind each eyeball. The rim of that hole is the lid edge, and the
edge loops around it are the lids. `lidlib.py` holds the maths that `sculpt_eyelids.py`,
`make_face_shapes.py` (eyeBlink, eyeWide, eyeSquint) and `bake_fish_skin.py` (the dark lash
line on the rim loop) share. Blinks turn the loops about the eye's horizontal axis and keep them
on a shell just outside the eyeball, so the smoothed lid still covers it. Keep the edge loops
around the eye hole when you edit the mesh, and re-run the face shapes afterwards.

## The spotted fish (fish_starter9)

`fish_starter9.blend` follows the artist's turnaround in `reference/turnaround.webp` (the six views
are cropped in `reference/turnaround/`). fish_starter10 above builds on it.
It was built from fish_starter8 by these scripts, in this order; re-run any step after changing
the one before it:

1. `rebuild_body.py`: keeps the face (eyes, mouth, teeth, tongue, all shape keys), lowers the
   forehead so the eyes sit at the top of the head, and lofts a new round body with a short tail
   stalk behind it, fitted to the reference (CENTER / RADII at the top of the script).
2. `make_fins.py`: the fins are separate meshes: ribbed fans with scalloped edges and real
   corrugation, rooted on the body by ray casting. Shapes are parameters in the script (`FINS`).
   Material `FishFin` is double-sided with a small generated texture.
3. `make_face_shapes.py`: the 44 face shapes, regenerated for the new head.
4. `bake_fish_skin.py`: salmon pink with magenta spots, fine scales, lighter belly and lips,
   four upper teeth, grey-blue eyes. Re-unwraps the head every run.
5. `rig_fish.py`: Root, Tail (bends the stalk, swings the tail fin), Dorsal, Fin.L/R, Anal; the
   fin meshes and eyes ride on their bones.
6. `make_swim.py`: the looping fin animation.
7. `export_fish.py`.

The `_v1` scripts (`bake_fish_skin_v1.py`, `rig_fish_v1.py`) belong to fish_starter7/8, whose
fins were part of the head mesh.

## The pink fish (fish_starter8)

`fish_starter8.blend` is the textured, rigged fish with the full face and the swim loop; the app
loads it from `public/models/fish.glb`. (`fish_starter7.blend` is the same fish one step earlier:
mirrored half mesh, no face shapes, no swim.)

- **Face.** 44 shape keys in Face Cap order: your `jawOpen`, plus brows, blinks, squints, wide
  eyes, cheeks, sneers, jaw sideways and forward, all mouth shapes and `tongueOut`. They are
  generated from the mesh by `blender/make_face_shapes.py`, which you can re-run after reshaping,
  or sculpt over by hand. The eight `eyeLook*` keys are left out on purpose: the app turns the eye
  objects for gaze, and would stop doing that if the model had eyeLook shapes. The mesh is a full
  mesh now (no Mirror modifier), because `_L` and `_R` shapes must move one side only; use
  Blender's X-mirror option when sculpting symmetric changes.
- **Swim.** The looping `swim` action (Rig, NLA track `swim`) sculls the pectoral and pelvic fins
  and ripples the dorsal fin, 1.2 s per stroke. The app plays a clip named `swim` or `idle` on a
  loop from the moment the model loads, underneath face tracking and actions; the tail is left to
  the app, which sways it harder while the singer sings. Recreate it with `blender/make_swim.py`,
  or edit it in the Action Editor (keep the first and last frame equal).

- **Skin.** The look is built procedurally in the `FishSkin_Source` material (pink skin, raised
  scale discs, freckles, white ribbed fins with pink roots and dark rims, dark mouth, white teeth,
  pink tongue) and baked into `textures/fish_basecolor.png` and `textures/fish_normal.png`. The
  exported material `FishBody` is only a Principled BSDF with those two images, which is what
  glTF and three.js understand. After sculpting, re-bake with
  `Blender -b blender/fish_starter8.blend -P blender/bake_fish_skin.py`.
- **Eyes.** `FishEye` uses the generated `textures/fish_eye.png` on a front-projected UV map, so the
  iris sits where the eye looks. Both eyes rest with no rotation; the app turns them for gaze.
- **Rig.** `Rig` has `Root` (body and eyes), `Tail` (vertical, so the app's sway swings it
  sideways), `Dorsal`, `Fin.L/R` and `Pelvic.L/R`. Weights are on the half mesh; the Mirror
  modifier makes the `.R` side. The face is driven by shape keys, not bones. Rebuild with
  `Blender -b blender/fish_starter8.blend -P blender/rig_fish.py`,
  then `make_swim.py` again.
- **Materials for three.js.** Anything that isn't a Principled BSDF fed by images or plain values
  (procedural textures, node groups, Mix Shaders) is lost on export. Bake it first.

## Facing and units

- The fish looks **toward -Y in Blender**, the direction Blender's Front view
  (numpad 1) looks at. The glTF exporter turns that into +Z in the app, toward
  the camera. Its top is +Z.
- Model at any size; the app scales the whole thing to fit the frame. Roughly
  2 metres nose to tail is a comfortable working size.
- Apply scale and rotation before exporting (Ctrl+A → All Transforms).

## Shape keys (blendshapes)

Face expressions come in as 52 ARKit weights. The app matches your shape keys
to them **by name**, so run `blender/add_facecap_shapekeys.py` on the head
mesh to create all 52 with the right names, then sculpt the ones you care
about. Accepted spellings, case-insensitive:

| Face Cap style | ARKit style | Blender-suffix style |
| --- | --- | --- |
| `eyeBlink_L` | `eyeBlinkLeft` | `eyeBlink.L` |

Unsculpted keys are fine; they just won't do anything. A fish needs far fewer
than 52. The ones that carry most of the performance:

- `jawOpen` (the big one), `mouthPucker`, `mouthFunnel`
- `mouthSmile_L/R`, `mouthFrown_L/R`
- `eyeBlink_L/R`, `eyeWide_L/R`
- `browInnerUp`, `browDown_L/R`, `browOuterUp_L/R`
- `cheekPuff`, `tongueOut`
- `eyeLook{Up,Down,In,Out}_L/R` if the eyes are part of the head mesh

Sides follow Blender's natural convention: `_L` is **the fish's own left**
(+X when it faces -Y), exactly like a `.L` bone. On stage the fish is the
singer's face seen from the front, so the singer's left lands on the fish's
left. For desk testing with the Mirror setting on, the app swaps the `_L` /
`_R` weights itself, so the keys never need renaming.

## Made for singing

The fish will be worn by a singer, so the mouth carries the performance. Spend the
sculpting time there:

- `jawOpen` must look good **held fully open** for seconds at a time, not just
  flicked. Check it at 1.0 for clipping through the head, lips, and teeth.
- Vowels are combinations: "ah" is `jawOpen`, "oo"/"oh" is `mouthFunnel` +
  `mouthPucker` (with some `jawOpen`), "ee" is `mouthStretch_L/R` (+ a bit of
  `mouthSmile`), "m"/humming is `jawOpen` + `mouthClose`. Sculpt `mouthClose` as
  "lips sealed while the jaw is dropped", which is what ARKit means by it.
- `mouthUpperUp_L/R`, `mouthLowerDown_L/R` and `mouthRollUpper/Lower` add teeth and
  lip detail if the fish has any.
- Singers close their eyes on long notes: `eyeBlink_L/R` should look calm when held
  at 1.0, and `eyeSquint_L/R` adds effort.
- `browInnerUp` and `browDown_L/R` sell emotion between phrases.
- Deep breaths read as `cheekPuff` and a small `jawOpen`; the app doesn't add
  anything for breath, so it's up to the shapes.

Shapes blend additively in glTF, so test combinations (jawOpen + mouthFunnel,
jawOpen + mouthSmile) in Blender's shape key panel before exporting.

### Mouth shapes in priority order

Names must match exactly; the app drives shape keys by these Face Cap names.

**Must have: the core of singing**

1. `jawOpen`: lower jaw and lower lip drop, teeth and tongue go with the jaw. The base
   for every open vowel.
2. `mouthFunnel`: lips forward into a round, open "O" ("oh", "aw").
3. `mouthPucker`: lips forward and tightly gathered, nearly closed ("oo", "w"). Keep it
   distinct from funnel: pucker is small and tight, funnel is round and open.
4. `mouthClose`: lips sealed while the jaw is down ("m", "b", "p"). Sculpt it with
   jawOpen dialled in; Face Cap only sends it together with jawOpen.
5. `mouthSmile_L` / `mouthSmile_R`: corners up and back, cheeks lifted ("ee", laughing).
6. `mouthStretch_L` / `mouthStretch_R`: corners straight out and a little down, the
   wide "ah"/"eh" of a belted note.

**Strongly recommended: shaping and consonants**

7. `mouthUpperUp_L/R`: upper lip up, showing upper teeth ("f", "v").
8. `mouthLowerDown_L/R`: lower lip down, showing lower teeth; strong on open vowels.
9. `mouthRollUpper` / `mouthRollLower`: lips roll in over the teeth.
10. `mouthPress_L/R`: lips flatten and press together.
11. `tongueOut`: tongue forward over the lower teeth ("l", "th").

**Nice to have: character**

12. `mouthFrown_L/R`, 13. `mouthShrugUpper` / `mouthShrugLower`,
14. `mouthLeft` / `mouthRight`, 15. `cheekPuff`,
16. `jawForward`, `jawLeft`, `jawRight`, `mouthDimple_L/R`.

Tips:

- Sculpt each shape alone from neutral, moving only what it needs: a vertex moved by
  two shapes moves twice.
- Test the pairs singers actually use: jawOpen + funnel, jawOpen + smile,
  jawOpen + mouthClose, pucker + a little jawOpen.
- **The "oo" problem.** For "oo" Face Cap sends a high pucker *and* some jawOpen (and
  often funnel). Sculpt `mouthPucker` with jawOpen at about 0.25 showing: turn on the
  "shape key edit mode" button (next to the shape key list) so edit mode shows the
  mix, then edit only the pucker key until the combination looks right.
- `_L` / `_R` pairs mirror each other; `_L` is the fish's own left (+X).
- Keep the teeth rigid with the jaw or the upper head in every shape.
- Leave all shape key sliders at 0 before exporting, or the exporter bakes them into
  the resting face.
- Name the eyeballs `Eye.L` (on +X) and `Eye.R` so the app turns them for gaze.

## Eyelids

Stretching the head skin over a bulging eyeball with shape keys tends to cut into the
eye halfway through a blink. A shape key moves each vertex in a **straight line**
from open to closed, and a straight line between two points outside a sphere passes
through it. Open and closed can both look fine while every in-between value clips.
glTF has no in-between shapes to correct this, so tuning shape keys can't fully fix it.

**What works: lids that rotate about the eye centre.** Rotation keeps every lid vertex
at the same distance from the centre, so a lid that starts just outside the eyeball
stays outside at every blink value.

- **Separate lid shells (recommended).** Per eye, an upper and a lower lid: a slice of
  a sphere slightly larger than the eyeball, tucked into the socket, skin-coloured
  with the lash line on its edge. Each is parented to its own bone placed at the eye
  centre, and a blink rotates the bone about the eye's sideways axis. This is the
  standard cartoon rig for big eyes and suits the heavy lids of the references.
- **Lid bones in the head skin.** The lid edge loops are weighted to a bone at the eye
  centre, so the head stays one mesh. Fully weighted vertices rotate cleanly;
  partially weighted ones still blend in straight lines and can clip a little.

Check a lid rig by scrubbing the rotation slowly and watching the halfway point, not
just fully closed.

The app currently drives blinks through morph targets (shape keys) named
`eyeBlink_L/R`, `eyeWide_L/R`, `eyeSquint_L/R`. Rotating lid bones need a small
addition in `src/fish/GltfFish.ts`: find the lid bones by name and turn them from those
values each frame, as it already does for the eyes and the tail. That is not built yet.

## Bones / empties

Head rotation is not a shape key. The app rotates a node named `Head` (or the
whole model if there is none). Other names it recognises, all optional:

| Name | Driven by |
| --- | --- |
| `Head` | head pitch / yaw / roll from Face Cap |
| `Jaw` | rotated on its X axis by jawOpen, only when there is no `jawOpen` shape key |
| `EyeL`, `EyeR` (or `Eye.L`, `Eye.R`) | gaze, only when there are no `eyeLook*` shape keys. Handy if the eyes are separate spheres. `EyeL` is the fish's own left (+X). |
| `Tail` | a gentle ambient sway |

Object names and bone names both work. Any other bones are left alone, so
you can keep rig helpers around.

## Actions (animation clips)

Body actions like a lap around the bowl can be authored in Blender and exported in
the same GLB. The app plays a clip by name when an action is triggered, and falls
back to a built-in procedural version when there is no clip.

- Make each action a Blender Action, then push it down to its own **NLA track**.
  Export with Animation → Animation mode: **NLA Tracks**, and Group by NLA Track
  ticked, so each track becomes one named clip.
- Name clips after the action: `lap`, `spin`, `nod`, `wiggle` (case matters; match
  the names in `src/actions/procedural.ts` or add new ones there).
- Clips animate the body: a root or body bone, fins, tail, location and rotation of
  the whole fish. **Never** key the `Head` bone or any shape key in a clip; face
  tracking owns those and would fight the clip.
- Clips must start and end at the rest pose, since tracking takes over the moment
  they finish.
- Keep the fish inside a couple of metres of the origin; the camera does not follow.
  For the lap, swim off one side, pass behind (the scene has fog, so it fades), and
  return from the other side facing front.

## Export

**With the scripts (recommended).** Save the .blend, then from the repo root:

```bash
B=/Applications/Blender.app/Contents/MacOS/Blender
$B -b blender/<fish>.blend -P blender/export_rest.py -P blender/export_fish.py
FACEFISH_NO_GLTF=1 $B -b blender/<fish>.blend -P blender/export_rest.py -P blender/export_fish.py -P blender/export_usd.py
```

- `export_rest.py`: rest pose (no animation, shape keys 0, bones at rest, fin-wave previews off) and
  writes `public/models/fish.rig.json` (fin wave settings, bone names).
- `export_fish.py`: `public/models/fish.glb` for the web app (shape keys rebuilt on the subdivided head).
- `export_usd.py`: `public/models/fish.usdz` for the iOS app, Y up; see `docs/ios-handoff.md`.
  Textures that aren't PNG or JPEG (the fins' PSDs) go into the USDZ as PNG copies.

**Fin ripple.** Each fin has a `FinWave` UV map (U: 0 at the root -> 1 at the edge, V: across the fan)
and a "FinWave preview" Geometry Nodes modifier: press play to see the ripple and tune Amplitude,
Wavelength, Speed, Falloff and Cross on the modifier. The export writes those values to rig.json and
the app and iOS run the same wave live; the preview itself is never baked into the export. Hiding a
preview in the viewport doesn't remove its ripple from the export; set Amplitude 0 for that. The old
Wave modifiers are Blender-only and are off.

**Fin rig.** One small armature per fin, all parented to Head: `TailRig` (bones `Tail.1`-`Tail.3`)
bends the skinned `Fin_Tail` about their X axes; `PecRig.L` (`Pec.L.0-2`) and `PecRig.R` (`Pec.R.0-2`)
bend the side fins (`.0` is a still root anchor; the others flap about X and sweep about Z).
`EyelidRig` holds only `Lid.L`/`Lid.R`. The app drives the fins with springs from head turns and nods.
Keep them separate: RealityKit merges every mesh skinned to one skeleton into a single model, so
fins sharing a rig load as one entity and the iOS app can't move them.

**Mouth shapes.** `blender/make_mouth_shapes.py` builds the Face Cap mouth keys the head was
missing (mouthUpperUp, LowerDown, Frown, Stretch, Dimple, Press, left and right; mouthRollUpper/Lower,
mouthShrugUpper/Lower, mouthLeft/Right) as a first pass to sculpt on. It finds the lip edge rings
around the mouth by itself and only moves vertices: no topology change, the teeth never move, and
your own keys (jawOpen, mouthClose, mouthFunnel, mouthPucker, mouthSmile) are never touched. The
sizes are at the top of the script; re-running overwrites only its own keys, so take a key out of
`SHAPES` once you've sculpted it by hand. Left = the fish's own left (+X), like mouthSmileLeft.

**Mirror the head.** `blender/mirror_head.py` makes the Head's basis exactly symmetric across X = 0
(each vertex and its twin move to their average; middle-line vertices to X = 0) and gives every shape
key the same correction, so expressions keep their movement. Re-run it whenever sculpting has
drifted one side; then re-run `make_mouth_shapes.py` so its keys are exact mirror pairs again.

**Brows and mirroring keys.** `blender/make_brow_shapes.py` creates the five Face Cap brow keys (each brow
turns about its eyeball's centre, so it slides over the eye) and an empty `tongueOut` to sculpt; it only
creates missing keys, so sculpted ones are safe. `blender/mirror_keys.py` makes one side's key from the
other's (e.g. `browDownLeft` as the mirror of `browDownRight`): edit `PAIRS` at the top and run it.

**Fin bake.** All fins share the texture UV map `FinUV` without overlapping (the two side fins are
stacked on purpose: mirror copies). `blender/bake_fins.py` bakes every fin into `fins_bake` in one
bake, with your current bake settings; baking fins one at a time with "Clear Image" on keeps only
the last one.

**By hand**, File → Export → glTF 2.0:

- Format: **glTF Binary (.glb)**
- Include → Limit to: Selected Objects (if you have helpers you don't want)
- Transform → **+Y Up** (default)
- Data → Mesh → **Shape Keys** ticked (under Mesh → Shape Keys in newer
  Blender). Leave **Apply Modifiers** off, or apply modifiers in Blender
  *before* adding shape keys: the exporter drops the shape keys of any mesh
  whose modifiers it applies.
- Data → Armature → Export Deformation Bones Only is fine
- Animation → NLA Tracks if you have action clips (see above), otherwise skip animations
- Keep textures small; the whole file should stay under ~10 MB for the iPad

Save as `public/models/fish.glb`, run `npm run dev` and the relay with
`--fake`, and watch the browser console: the app logs which shape keys and
nodes it matched.
