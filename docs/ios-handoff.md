# Facefish on iOS (RealityKit): handoff

This is the spec for rebuilding the Facefish avatar natively on iOS with RealityKit. It is written for
the iOS developer and their AI assistant: every rule, number and name the fish needs is here, and the
web app in this repo is the reference implementation that behaves exactly this way today. When this
document and the code disagree, the code wins; file references are given for each part.

**Status of what was verified.** The model files, their structure and names below were checked by
reading the exported USDZ with the USD library. The behaviour (formulas, constants) is what the web app
runs. Nothing here has been run in RealityKit yet; the points that need checking on the device are
marked **Verify**.

## 1. What you are building

```
iPhone with Face ID, Face Cap app (Live Mode, OSC)  --UDP, Wi-Fi-->  iPad app (RealityKit)  --HDMI-->  screen in the helmet
```

- Face Cap tracks the singer's face (ARKit on the iPhone) and streams values over OSC/UDP, about 50-60
  frames per second, to port **8080** on the iPad.
- The iPad app parses OSC, maps the values to the fish (shape keys, eyes, lids, head, tail springs,
  fin ripple) and renders it. The fish is shown full screen on an external display over HDMI.
- No laptop or relay is needed on stage. (The web app needs a Node relay only because browsers cannot
  receive UDP; a native app can.)

## 2. Files

All in `public/models/`, produced from the artist's Blender file by the export scripts in `blender/`:

| File | What it is |
| --- | --- |
| `fish.usdz` | **The model for iOS.** Y up, metres. Shape keys as USD blend shapes, tail bones as a UsdSkel skeleton, fin wave map as a second UV set. Made by `blender/export_usd.py`. |
| `fish.rig.json` | Per-model numbers: fin wave settings per fin, bone names. Read it at runtime or bake it into code. Made by `blender/export_rest.py`. |
| `fish.glb` | Same fish for the web app (three.js). Useful as a visual reference. |
| `recordings/take-*.json` | Recorded Face Cap performances (not in Git; ask for one). Replay them to the iPad with `relay/replay.mjs`, see section 11. |

Re-export after the artist changes the model (run from the repo root; the .blend must be saved):

```bash
B=/Applications/Blender.app/Contents/MacOS/Blender
F=blender/fish_david_AppliedMirror_keys3.blend
$B -b $F -P blender/export_rest.py -P blender/export_fish.py
FACEFISH_NO_GLTF=1 $B -b $F -P blender/export_rest.py -P blender/export_fish.py -P blender/export_usd.py
```

### 2.1 Scene structure in `fish.usdz`

Read from the file (the artist's names; USD turns `.` into `_`):

```
/root                         Xform  rotateX -90: the Z-up -> Y-up conversion, nothing else
  /Fish                       Xform  turn this for head pose and move it for head travel
    /Head                     SkelRoot
      /Plane_001              Mesh   the head; 24 mouth blend shapes named like ARKit (jawOpen, mouthClose,
                                     mouthFunnel, mouthPucker, mouthLeft/Right, mouthSmileLeft/Right,
                                     mouthFrown*, mouthDimple*, mouthStretch*, mouthPress*, mouthUpperUp*,
                                     mouthLowerDown*, mouthRollUpper/Lower, mouthShrugUpper/Lower)
      /Skel                   Skeleton (joint1): dummy skeleton USD needs for blend shapes
    /Eye_L, /Eye_R            Xform + Mesh  eyeballs; pivot = eyeball centre; rotate for gaze
    /Eyelid_L, /Eyelid_R      Xform + Mesh  upper lids; pivot = eyeball centre; rotate for blinks
    /EyelidRig                Xform
      /EyelidRig              Skeleton  joints Lid_L, Lid_R (nothing skinned to them; see below)
    /TailRig                  SkelRoot  one small skeleton per fin, so each fin is its own model entity
      /TailRig                Skeleton  joints Tail_1, Tail_1/Tail_2, Tail_1/Tail_2/Tail_3
      /Fin_Tail               Xform + Mesh  skinned to TailRig; uv sets FinUV, FinWave
    /PecRig_L                 SkelRoot
      /PecRig_L               Skeleton  joints Pec_L_0, Pec_L_0/Pec_L_1, Pec_L_0/Pec_L_1/Pec_L_2
      /Fin_Pectoral_L         Xform + Mesh  left side fin, skinned to PecRig_L; uv sets FinUV, FinWave
    /PecRig_R                 SkelRoot  the same for the right side fin (Pec_R_*, Fin_Pectoral_R)
    /Fin_Dorsal               Xform + Mesh  uv sets FinUV, FinWave (scale 0.765 on the Xform); no bones yet
    /Mid                      empty Xform, ignore
```

- Find things **by name, ignoring case, `.`, `_` and spaces** (`Eye.L`, `Eye_L` and `eyel` are the
  same). Names are stable conventions agreed with the artist; mesh prim names under them (`Plane_001`,
  `Sphere_001`, ...) are not, so look up the Xform/joint names, never the mesh names.
- The `Lid_L`/`Lid_R` joints exist but nothing is skinned to them in the USDZ (USD can't parent a mesh
  to a joint). **Turn the `Eyelid_L`/`Eyelid_R` entities instead**; their origin is the pivot and
  their local X is the blink axis, so that is identical.
- Each skinned fin has **its own skeleton** (`TailRig`, `PecRig_L`, `PecRig_R`). RealityKit merges all
  meshes bound to one skeleton into a single `ModelEntity`, which is why the fins didn't move when they
  shared one rig. Now each fin loads as its own single-mesh `ModelEntity` (at `TailRig`, `PecRig_L`,
  `PecRig_R`); set that entity's `jointTransforms`.
- **Verify**: that RealityKit gives `Eye_L`, `Eye_R`, `Eyelid_L`, `Eyelid_R`, `Fin_Dorsal`, the three
  fin rigs and `Fish` as separate entities you can transform, and that the head mesh exposes its
  blend shapes.
- Fins: material `FishFin.001` has a colour texture and an opacity texture (`fins.png`, `fins_opacity.png`);
  render the fins with alpha blending.
- Model size: about 56k triangles (fins have thickness). Fine for a recent iPad; tell us if not.
- A lid texture (`lid_test.png`) is missing in the artist's file and is not in the USDZ yet.

### 2.2 Axes (important)

`/root` holds the only Y-up conversion. **Every entity below it keeps Blender's local axes**:

| Local axis (entities under `/root`) | Means |
| --- | --- |
| +X | the fish's left (screen right when the fish faces you) |
| +Z | up |
| -Y | forward: the way the fish faces (toward the viewer) |

So, in each entity's **local** space: left-right turns (yaw) are about **local Z**, nods (pitch) about
**local X**, tilts (roll) about **local Y**. All rotations below are applied as
`orientation = restOrientation * delta` (local), except where noted.

## 3. Face Cap input (OSC over UDP)

Listen on UDP 8080 (Face Cap: Live Mode, OSC, the iPad's IP, port 8080). Packets are OSC 1.0
messages, sometimes bundles (`#bundle`, may be nested). Face Cap sends each value as its own datagram,
~57 per frame. Keep the latest value of everything; a "frame" is just the current state.

| Address | Args | Meaning |
| --- | --- | --- |
| `/W` | int index, float value | blendshape weight 0..1, index into the table below |
| `/HR` | 3 floats | head rotation, degrees: x = pitch, y = yaw, z = roll |
| `/HT` | 3 floats | head position, centimetres |
| `/HRQ` | 4 floats | head rotation as quaternion (unused) |
| `/ELR`, `/ERR` | 2 floats | eye rotations (unused: gaze comes from the eyeLook blendshapes) |
| `/action <name>` or `/action/<name>` | | show cue (web app: lap, spin, nod, ...) |

Blendshape index table (Face Cap order, `src/facecap/blendshapes.ts`):

```
 0 browInnerUp     1 browDown_L      2 browDown_R      3 browOuterUp_L   4 browOuterUp_R
 5 eyeLookUp_L     6 eyeLookUp_R     7 eyeLookDown_L   8 eyeLookDown_R   9 eyeLookIn_L
10 eyeLookIn_R    11 eyeLookOut_L   12 eyeLookOut_R   13 eyeBlink_L     14 eyeBlink_R
15 eyeSquint_L    16 eyeSquint_R    17 eyeWide_L      18 eyeWide_R      19 cheekPuff
20 cheekSquint_L  21 cheekSquint_R  22 noseSneer_L    23 noseSneer_R    24 jawOpen
25 jawForward     26 jawLeft        27 jawRight       28 mouthFunnel    29 mouthPucker
30 mouthLeft      31 mouthRight     32 mouthRollUpper 33 mouthRollLower 34 mouthShrugUpper
35 mouthShrugLower 36 mouthClose    37 mouthSmile_L   38 mouthSmile_R   39 mouthFrown_L
40 mouthFrown_R   41 mouthDimple_L  42 mouthDimple_R  43 mouthUpperUp_L 44 mouthUpperUp_R
45 mouthLowerDown_L 46 mouthLowerDown_R 47 mouthPress_L 48 mouthPress_R 49 mouthStretch_L
50 mouthStretch_R 51 tongueOut
```

`_L` is the **singer's** left. "Live" means a packet arrived within the last **1.5 s**; otherwise run
the idle behaviour (section 9).

Latency matters more than anything for a singer: parse on a background queue, hand the latest state
to the render loop, never queue frames. Wi-Fi tips are in the main README ("The iPhone -> iPad link").

## 4. Mapping pipeline (per rendered frame)

Reference: `src/fish/mapping.ts` (`fromFrame`, `update`). Settings and defaults:

| Setting | Default | Notes |
| --- | --- | --- |
| expression | 1.3 | gain on every blendshape |
| mirror | false | false = the fish is the singer's face seen from the front (helmet). true = like a mirror (desk testing) |
| smoothing | 0.3 | 0 = raw |
| puckerPriority | 1 | how much a pucker turns funnel down (step 2b) |
| headGain | 1 | head turn of the fish; 0 keeps the fish facing front |
| moveGain | 1 | head travel inside the helmet -> fish travel |
| headLimit | 55° | |
| eyeRange | 0.45 rad | full look |
| lidAngle | 77° | full blink, from the modelled lid (which sits about 23° down already) |
| lidNeutral | 0 | extra closing with no blink (0 = as modelled) |
| finReaction | 1 | tail reaction strength (negative flips the side) |
| finSway | 1 | tail idle sway |
| finWave / finWaveSpeed | 1 / 1 | multipliers on the fin ripple from rig.json |
| autoCenter | 30 s | slow re-learning of the head's rest pose |

0. **Face calibration ("Center face").** Face Cap rarely reads 0 on a relaxed face (this singer:
   mouthStretch ~0.3, jawOpen ~0.08, eyeSquint and eyeWide ~0.2). Give the operator a "Center face"
   button: for 1.5 s of live tracking, store the **median** of each raw value as `rest[i]` (a median, so
   a blink in between doesn't count), and keep it on the device. Then, before the gain:
   `raw[i] = rest[i] >= 0.95 ? raw[i] : max(0, (raw[i] - rest[i]) / (1 - rest[i]))`.
   The resting face reads 0 everywhere and a full expression still reaches 1. Without a stored rest,
   skip this step. Takes recorded from the web app carry the rest it used as `"neutral"` (52 numbers).
1. **Gain:** `w[i] = clamp(raw[i] * expression, 0, 1)`.
2. **Sides for the model:** if `mirror`, swap every `_L` with its `_R` (`modelW[i] = w[mirrorOf(i)]`),
   else `modelW = w`. Model shape keys named `..._L` / `...Left` are the **fish's** left.
2b. **Pucker priority** (default 1): `modelW.mouthFunnel *= 1 - puckerPriority * modelW.mouthPucker`.
   The artist's pucker is a very narrow kiss; with funnel at full strength on top, the sides of the
   mouth would cross (a whistle sends both high). The more the singer puckers, the less funnel.
3. **Smoothing** (exponential, frame-rate independent). `s = smoothing`:
   `kFast = s <= 0 ? 1 : 1 - exp(-dt * 28 / s)`, `kSlow = s <= 0 ? 1 : 1 - exp(-dt * 14 / s)`.
   Every value: `smoothed += (target - smoothed) * k`. While live, **all blendshape weights use kFast**.
   Head pose uses kSlow, except `turn`, gaze and blinks which use kFast.
4. **Head rest pose:** on the first live frame (and when the operator presses "center"), take the
   current `/HR` and `/HT` as neutral. If autoCenter > 0, every frame
   `neutral += (current - neutral) * (1 - exp(-dt / 30))`.
5. **Head pose** (radians; `side = mirror ? 1 : -1`, `ys = mirror ? -1 : 1`):

   ```
   pitch = clamp(hr.x - n.x, ±55°) * headGain
   yaw   = clamp(hr.y - n.y, ±55°) * headGain * ys
   roll  = clamp(hr.z - n.z, ±55°) * headGain * ys
   turn  = clamp(hr.y - n.y, ±55°) * ys          // NOT scaled by headGain; drives the tail
   ```

   Apply to the **`Fish`** entity, about its parent's axes (pre-multiply), in local axes of section 2.2:
   `Fish.orientation = rotZ(yaw) * rotX(pitch) * rotY(-roll) * restOrientation`
   (yaw positive turns the face toward the fish's left; pitch positive nods down).
   The web app turns the Head node the same way (`GltfFish.update`).
6. **Head travel** (the singer's head moves inside a helmet fixed to the shoulders):
   `x = clamp(ht.x - n.x, ±20) * 0.05 * moveGain * side`, `y = clamp(ht.y - n.y, ±20) * 0.05 * moveGain`,
   `z = clamp(ht.z - n.z, ±20) * 0.05 * moveGain` (toward the viewer). These are in units where the
   fish's largest dimension is 2.4, so in metres multiply by `fishSize / 2.4`. Plus a gentle bob:
   `y += 0.03 * sin(0.9 * time)` (same units). Move the `Fish` entity by (x, y, z) in **Y-up world**
   (or convert to its local: world +Y = local +Z, world +Z = local -Y).

## 5. Shape keys (blend shapes)

For every blend shape on the head whose name matches a Face Cap name, set its weight to the smoothed
`modelW` of that name each frame. Match ignoring case and separators, and accept ARKit spelling:
`eyeBlink_L`, `eyeBlink.L`, `eyeBlinkLeft` are all index 13. Unmatched shapes stay 0. In mirror mode swap `mouthLeft`/`mouthRight` and `jawLeft`/`jawRight` too, like every `_L`/`_R` pair.
The artist adds more shapes over time (priority list in `blender/README.md`); no code change needed.

**Verify**: RealityKit blend shape API (iOS 18+: `BlendShapeWeightsComponent` /
`BlendShapeWeightsMapping`) and that names arrive as in the USD (`jawOpen`, `mouthSmileLeft`, ...).

## 6. Eyes (gaze)

The eyes turn about their own centre. Inputs are the gained weights `w` (singer's sides). With
`mirror = false`:

```
Eye_L.yaw   = (w.eyeLookOut_L  - w.eyeLookIn_L ) * 0.45     // +: look toward the fish's left (+X)
Eye_L.pitch = (w.eyeLookDown_L - w.eyeLookUp_L ) * 0.45     // +: look down
Eye_R.yaw   = (w.eyeLookIn_R   - w.eyeLookOut_R) * 0.45
Eye_R.pitch = (w.eyeLookDown_R - w.eyeLookUp_R ) * 0.45
```

With `mirror = true` use the other eye's values (`_L` <-> `_R` swapped on the right-hand sides).
Smooth with kFast. Apply in the eye's local axes: `Eye.orientation = rest * rotZ(yaw) * rotX(pitch)`.
(Web app: `mapping.ts` eye section + `GltfFish.update`.)

## 7. Eyelids (blink, wide, squint)

The lids rotate about the eyeball centre, so they never cut into the eye mid-blink. Per fish side
(`_L` = the fish's left), from the **model** weights (`modelW`, after mirroring), smoothed with kFast:

```
amount = clamp(blink + 0.35 * squint - 0.25 * wide, -0.3, 1)      // eyeBlink_X, eyeSquint_X, eyeWide_X
closed = amount >= 0 ? lidNeutral + (1 - lidNeutral) * amount       // lidNeutral = 0: the model's lids are already at their neutral
                     : lidNeutral + amount * (lidNeutral + 0.3) / 0.3   // wide eyes: up to 0.3 past the modelled lid
Eyelid_X.orientation = rest * rotX(radians(lidAngle * closed))    // lidAngle = 77; positive closes
```

## 8. Tail reaction (springs) and swim sway

All fin motion (tail, side fins, ripple) is also written up on its own, with a Swift sketch of the
springs, in [ios-fins.md](ios-fins.md).

The tail fin is skinned to three joints, root to tip: `Tail_1`, `Tail_1/Tail_2`, `Tail_1/Tail_2/Tail_3`
(in RealityKit the joint names may be the full paths). Each turns about its own **local X**; a positive
angle swings the tail toward the fish's **right**. Reference: `GltfFish.updateTail`.

Every frame (`dt` seconds, clamp dt to <= 0.1):

```
// 1. how fast the singer turns their head (rad/s), lightly smoothed
rate      = (turn - lastTurn) / dt;   lastTurn = turn
turnRate += (rate - turnRate) * (1 - exp(-dt * 18))

// 2. bone 1 is pulled toward a target; each next bone follows the previous one (follow-through)
target0   = clamp(-turnRate * 0.35 * finReaction, -0.8, 0.8)       // radians
stiffness = 70;  damping = 2 * 0.32 * sqrt(stiffness)              // under-damped: small overshoot
steps     = max(1, ceil(dt / (1/120)));  h = dt / steps            // 120 Hz sub-steps
repeat steps times:
    target = target0
    for bone in chain (root to tip):
        acc        = stiffness * (target - bone.angle) - damping * bone.vel
        bone.vel  += acc * h
        bone.angle+= bone.vel * h
        target     = bone.angle

// 3. idle swim sway, a wave travelling down the chain, livelier while singing
energy = 0.6 + 1.2 * min(1, mouthOpen)                              // mouthOpen: see below
for bone i (0 = root):
    sway = 0.1 * finSway * energy * sin(4.2 * time - 0.9 * i)
    joint[i].rotation = rest[i] * rotX(bone.angle + sway)
```

`mouthOpen = max(w.jawOpen, 0.5 * w.mouthFunnel) * (1 - 0.85 * w.mouthClose)`, smoothed with kFast
(the web app's `pose.jawOpen`). It also livens the fin ripple (section 10).

What it looks like: when the singer turns their head, the tail bends toward the side they turn to
(it lags behind the turn), overshoots a little and wobbles back, the bend rippling out to the tip.

### 8.1 Side (pectoral) fins

Each side fin is skinned to a chain: `Pec_X_0` (a short **anchor** at the root: never rotate it; it
keeps the fin's seam on the body), then `Pec_X_1`, `Pec_X_2` (root to tip), X = L or R. Each chain bone
has **two springs**: `flap` about its local **X** (+ = fin tip up, on both sides) and `sweep` about
its local **Z** (+ sweeps the left fin back and the right fin forward). Reference:
`GltfFish.updateSideFins`.

```
// inputs (shared with the tail): turnRate as in section 8, and the nod rate:
nod      = clamp(hr.x - n.x, ±55°)                     // radians, + = head down; NOT scaled by headGain
nodRate += ((nod - lastNod) / dt - nodRate) * (1 - exp(-dt * 18));  lastNod = nod

side       = +1 for the left fin, -1 for the right fin
flapTarget = clamp(nodRate * 0.3 * finReaction, -0.6, 0.6)            // head dips -> both fins lift
forward    = clamp(side * turnRate * 0.3 * finReaction, -0.6, 0.6)    // turning toward this fin's side:
sweepTarget= -side * forward                                          //   it flares forward, the other tucks back
stiffness  = 55;  damping = 2 * 0.35 * sqrt(stiffness);  120 Hz sub-steps
repeat steps:  tf = flapTarget; ts = sweepTarget
    for bone in [Pec_X_1, Pec_X_2]:
        bone.flapVel  += (stiffness*(tf - bone.flap)  - damping*bone.flapVel)  * h;  bone.flap  += bone.flapVel  * h
        bone.sweepVel += (stiffness*(ts - bone.sweep) - damping*bone.sweepVel) * h;  bone.sweep += bone.sweepVel * h
        tf = bone.flap;  ts = bone.sweep                                    // follow-through to the tip

// gentle sculling at rest (finSway, energy as in section 8), right fin slightly behind the left
phase = side > 0 ? 0 : 0.5
for bone i (0 = Pec_X_1):
    a     = 5.6 * time + phase - 0.7 * i
    flap  = bone.flap  + 0.14 * finSway * energy * sin(a)
    sweep = bone.sweep - side * 0.08 * finSway * energy * sin(a + 1.2)
    joint.rotation = rest * rotX(flap) * rotZ(sweep)
```

The dorsal fin has no bones yet (only the ripple). The same pattern extends to it.

**Verify**: setting `jointTransforms` on the skinned `Fin_Tail` model entity each frame.

## 9. Idle (no tracking for 1.5 s)

So the fish is never frozen between songs (`mapping.ts` `idle`):

- blink every 2.5-5.5 s (random): `blink = sin(phase * π)`, phase 0 -> 1 over 0.2 s
- jawOpen `0.12 + 0.1 * (0.5 + 0.5 sin(2.1 t))`, both smiles 0.15, pucker 0.1
- gaze yaw `0.25 sin(0.45 t)`, pitch `0.12 sin(0.7 t + 1)` (radians)
- head yaw `10° sin(0.5 t)` (also used as `turn`), pitch `4° sin(0.8 t + 2)`, roll `4° sin(0.35 t + 1)`
- drift x `0.05 sin(0.4 t)`, y `0.04 sin(0.9 t)` (2.4-units, see 4.6)

Blend into idle and back with the kSlow smoothing (kFast for blinks/gaze), as the web app does.

## 10. Fin ripple (resting wave through the fins)

A wave travels from each fin's root to its edge; the root never moves, the edge moves most. It runs on
the GPU, before skinning, so the tail springs stack on top. Reference: `src/fish/finWave.ts`.

Each fin mesh has a second UV set **`FinWave`** (uv1): `U` = 0 at the root -> 1 at the outer edge,
`V` = position across the fan (0..1). Per fin, from `fish.rig.json` -> `finWave.fins[<name>]`:

```
offset = axisUsd * amplitude * U^falloff * sin(2π * (U / wavelength - phase + V * cross))
phase += speed * finWaveSpeed * (1 + 0.6 * min(1, mouthOpen)) * dt    // per fin; accumulate, don't use time*speed
amplitude *= finWave
```

- Use **`axisUsd`** (fin mesh space in Blender/USD axes); `axis` is for the glTF.
- `amplitude` is in mesh units at the outer edge; the Xform's scale (0.765 on the dorsal) applies on top.
- Current values (all fins share wavelength 4.04, speed 0.8, falloff 3.08, cross 2.11; amplitude scales
  with fin length): Fin_Tail 0.151, Fin_Dorsal 0.150, Fin_Pectoral_L/_R 0.127. Always read rig.json;
  the artist tunes these in Blender.

RealityKit sketch, one geometry modifier per fin (the axis and cross baked in as constants from
rig.json, the per-frame values passed in `custom`):

```metal
#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
using namespace metal;

// custom: x = amplitude * finWave, y = wavelength, z = falloff, w = phase
[[visible]] void finWaveTail(realitykit::geometry_parameters params) {
    const float3 AXIS  = float3(1.0, 0.0, 0.0);   // rig.json Fin_Tail.axisUsd
    const float  CROSS = 2.11;                     // rig.json Fin_Tail.cross
    float4 c  = params.uniforms().custom_parameter();
    float2 fw = params.geometry().uv1();           // FinWave
    float  u  = clamp(fw.x, 0.0, 1.0);
    float  s  = sin(6.2831853 * (u / c.y - c.w + fw.y * CROSS));
    params.geometry().set_model_position_offset(AXIS * c.x * pow(u, c.z) * s);
}
```

```swift
// once: wrap each fin's material
var fin = try CustomMaterial(from: original,
                             geometryModifier: .init(named: "finWaveTail", in: device.makeDefaultLibrary()!))
// each frame: update phase, write back (materials are value types)
fin.custom.value = SIMD4<Float>(amplitude * finWave, wavelength, falloff, phase)
model.materials = [fin]
```

**Verify**: that `uv1()` is the FinWave set (if V looks flipped, use `1 - fw.y`; U should read 0 at the
root), that the offset on the skinned `Fin_Tail` is applied before skinning (if not, the wave still
works but is not bent by the tail bones), and that the fins render double sided.

## 11. Tools for development (no iPhone or singer needed)

From the repo root, with Node installed:

| Command | What it does |
| --- | --- |
| `node relay/replay.mjs --to <ipad-ip>:8080 --loop` | Replays the newest recorded take as live Face Cap OSC to the iPad. `--speed 0.5` for slow motion; pass a take file to choose. |
| `npm run relay` + `npm run dev` | The web app with live Face Cap (open the printed URL). Compare side by side with the iPad: run `replay.mjs` twice, once to the relay (`127.0.0.1:8080`) and once to the iPad. |
| `npm run relay -- --fake` | Synthetic Face Cap data to the web app. |
| In the web app: `v` | Key monitor: every incoming value, what the fish receives, which shapes the model lacks. |
| In the web app: `r` | Record a take to `recordings/` (from Face Cap). |
| `blender/import_take.py` | Replays a take as keyframes in Blender (for the artist). |

Take format (`recordings/take-*.json`): `{ "names": [52 names], "sampleRate": 60, "frames": [ { "t": s,
"w": [52], "hr": [3 deg], "ht": [3 cm], "el": [2], "er": [2] } ] }`, raw values (no gain or mirroring).

## 12. Acceptance checklist

Run a take with `replay.mjs` to the iPad and to the web app at the same time and compare:

- [ ] mouth: jawOpen, funnel, pucker, smiles match the web app frame for frame (use the same resting face:
      the take's `"neutral"`)
- [ ] Center face: with a relaxed face the mouth closes fully and the lids sit as modelled
- [ ] blinks close both lids fully at 77° (from the modelled lid); winks close one lid; squint drops it a bit; wide lifts it
- [ ] eyes look the same way as the singer (with mirror off, the singer looking to their left turns the
      fish's eyes toward the fish's left, screen right)
- [ ] head turn: the fish turns (headGain 1) and the tail lags, overshoots and settles; the inside side
      fin flares forward, the outside one tucks back; with headGain 0 the fish stays put but the fins still react
- [ ] nod: both side fins lift and wobble back as a mirror pair; at rest they scull gently
- [ ] fins ripple at rest, roots still, edges ~11-15 cm, livelier while singing
- [ ] idle after 1.5 s without data: blinking, slow mouthing, drifting
- [ ] latency: compare to Face Cap's own preview; target well under 100 ms end to end

## 13. Out of scope here (exists in the web app)

Body actions (lap, spin, nod, ...) triggered by OSC `/action` and keys (`src/actions/`), the underwater
look (caustics, tint, bubbles, helmet interior: `src/water/`, `src/scene.ts`), the control panel. Port
later if wanted; the cue protocol is in section 3.
