# Fins: reactions and ripple (iOS / RealityKit spec)

How the Facefish fins move, for the iOS app. Three layers run together every frame:

1. **Tail reaction**: when the singer turns their head, the tail lags, overshoots and wobbles back,
   the bend rippling out to the tip. A slow swim sway runs underneath.
2. **Side fins**: nods lift both side (pectoral) fins; on a turn the fin on the inside flares
   forward like a brake while the outer one tucks back. At rest they scull gently.
3. **Fin ripple**: a wave travels from each fin's root to its edge on all four fins, computed on the
   GPU. The root never moves; the edge moves most. It is added before the bones bend the fin, so it
   stacks with 1 and 2.

The web app in this repo runs exactly this (reference: `src/fish/GltfFish.ts` `updateRates`,
`updateTail`, `updateSideFins`, and `src/fish/finWave.ts`). The wider spec (input, face, eyes, lids)
is `docs/ios-handoff.md`.

## 1. What the model gives you

`public/models/fish.usdz` (Y up, metres). Everything below `/root` keeps Blender's local axes:
**+X = the fish's left, +Z = up, -Y = forward** (the way the fish faces). Names lose their dots in
USD (`Tail.1` -> `Tail_1`); match names ignoring case, `.` and `_`.

| Part | In the USDZ | Moves by |
| --- | --- | --- |
| Tail fin | mesh `Fin_Tail`, skinned | joints `Tail_1`, `Tail_1/Tail_2`, `Tail_1/Tail_2/Tail_3` (root to tip) |
| Left side fin | mesh `Fin_Pectoral_L`, skinned | joints `Pec_L_0` (anchor), `Pec_L_0/Pec_L_1`, `Pec_L_0/Pec_L_1/Pec_L_2` |
| Right side fin | mesh `Fin_Pectoral_R`, skinned | same with `Pec_R_*` |
| Dorsal fin | mesh `Fin_Dorsal` (scale 0.765 on its Xform) | ripple only, no bones yet |

All four fin meshes have a second UV set **`FinWave`** (uv1) for the ripple. Each skinned fin has its
own skeleton, so RealityKit loads it as its own single-mesh `ModelEntity`:

| Fin | SkelRoot (the `ModelEntity`) | Skeleton | Mesh |
| --- | --- | --- | --- |
| Tail | `/root/Fish/TailRig` | `/root/Fish/TailRig/TailRig` | `/root/Fish/TailRig/Fin_Tail` |
| Left side | `/root/Fish/PecRig_L` | `/root/Fish/PecRig_L/PecRig_L` | `/root/Fish/PecRig_L/Fin_Pectoral_L` |
| Right side | `/root/Fish/PecRig_R` | `/root/Fish/PecRig_R/PecRig_R` | `/root/Fish/PecRig_R/Fin_Pectoral_R` |

(They used to share one skeleton, `EyelidRig`. RealityKit then merged the three fins into one model
and they didn't move.)

Joint axes (each joint's own local frame):

| Joint | + about local X | + about local Z |
| --- | --- | --- |
| `Tail_*` | swings the tail toward the fish's **right** | (unused) |
| `Pec_L_1`, `Pec_L_2` | flaps the fin **up** | sweeps the fin **back** |
| `Pec_R_1`, `Pec_R_2` | flaps the fin **up** | sweeps the fin **forward** |
| `Pec_X_0` | never rotate: it pins the fin's root seam to the body | |

Apply every joint rotation as `rest * delta` (local), where `rest` is the joint's bind/rest rotation.

`public/models/fish.rig.json` holds the per-fin ripple settings (section 4) and the bone list. Read it
at runtime, or bake its numbers into code when the model is final.

## 2. Inputs (computed every frame)

From Face Cap's head rotation `/HR` (degrees, x = pitch, y = yaw) relative to the rest pose `n` (see
`ios-handoff.md` section 4: neutral = first live frame, slowly re-learned, re-centred on demand):

```
turn = radians(clamp(hr.y - n.y, -55, 55)) * (mirror ? -1 : 1)    // + = toward the fish's left
nod  = radians(clamp(hr.x - n.x, -55, 55))                         // + = head down
```

These are deliberately NOT scaled by the head-turn setting: the fins react to the singer's head even
when the fish itself is kept facing front.

Rates (rad/s), lightly smoothed, for every `dt` (seconds, clamp to <= 0.1):

```
k        = 1 - exp(-dt * 18)
turnRate += ((turn - lastTurn) / dt - turnRate) * k;   lastTurn = turn
nodRate  += ((nod  - lastNod ) / dt - nodRate ) * k;   lastNod  = nod
```

Singing energy, from the gained Face Cap weights `w` (0..1, after the 1.3 expression gain), smoothed
like the mouth (fast rate):

```
mouthOpen = max(w.jawOpen, 0.5 * w.mouthFunnel) * (1 - 0.85 * w.mouthClose)
energy    = 0.6 + 1.2 * min(1, mouthOpen)
```

Settings (all default 1): `finReaction` (strength of the spring reactions; negative flips them),
`finSway` (rest motion), `finWave` (ripple height), `finWaveSpeed` (ripple speed).

When no tracking arrives for 1.5 s the app idles, and `turn` / `nod` follow the idle head motion
(`turn = 10° sin(0.5 t)`, `nod = 4° sin(0.8 t + 2)`), so the fins keep living.

## 3. Springs

All reactions use a damped spring per value, integrated in fixed 120 Hz sub-steps:

```
steps = max(1, ceil(dt / (1/120)));  h = dt / steps
repeat steps:
    vel   += (stiffness * (target - angle) - damping * vel) * h
    angle += vel * h
```

In a chain (root to tip) each bone's target is the previous bone's angle, so motion travels outward
(follow-through). Damping = `2 * ratio * sqrt(stiffness)`; a ratio below 1 gives a small overshoot.

### 3.1 Tail

```
target0 = clamp(-turnRate * 0.35 * finReaction, -0.8, 0.8)     // rad; the tail bends toward the turn side
stiffness 70, damping ratio 0.32
chain Tail_1 -> Tail_2 -> Tail_3 (each follows the previous)

sway(i) = 0.1 * finSway * energy * sin(4.2 * time - 0.9 * i)   // i = 0 at Tail_1
Tail_i.rotation = rest_i * rotX(angle_i + sway(i))
```

### 3.2 Side fins

Per fin, `side = +1` (left) / `-1` (right); two springs per chain bone (`flap`, `sweep`):

```
flapTarget  = clamp(nodRate * 0.3 * finReaction, -0.6, 0.6)                 // head dips -> both fins lift
forward     = clamp(side * turnRate * 0.3 * finReaction, -0.6, 0.6)         // + when turning toward this fin
sweepTarget = -side * forward                                               // flare forward / tuck back
stiffness 55, damping ratio 0.35
chain Pec_X_1 -> Pec_X_2 for both springs (each follows the previous)

// sculling at rest, the right fin a little behind the left
phase   = side > 0 ? 0 : 0.5
a(i)    = 5.6 * time + phase - 0.7 * i                                      // i = 0 at Pec_X_1
flap_i  = flapSpring_i  + 0.14 * finSway * energy * sin(a(i))
sweep_i = sweepSpring_i - side * 0.08 * finSway * energy * sin(a(i) + 1.2)
Pec_X_i.rotation = rest_i * rotX(flap_i) * rotZ(sweep_i)                   // Pec_X_0 stays at rest
```

### 3.3 Swift sketch

```swift
import simd

struct Spring {
    var angle: Float = 0, vel: Float = 0
    mutating func step(to target: Float, stiffness k: Float, ratio: Float, h: Float) {
        vel += (k * (target - angle) - 2 * ratio * k.squareRoot() * vel) * h
        angle += vel * h
    }
}

/// Per frame: angles in radians, about each joint's local axes.
struct FinPose {
    var tail: [Float] = [0, 0, 0]                  // Tail_1..3, about X
    var pecFlap: [[Float]] = [[0, 0], [0, 0]]      // [left, right][Pec_X_1, Pec_X_2], about X
    var pecSweep: [[Float]] = [[0, 0], [0, 0]]     // about Z
}

final class FinRig {
    var finReaction: Float = 1, finSway: Float = 1
    private var lastTurn: Float?, lastNod: Float?
    private var turnRate: Float = 0, nodRate: Float = 0
    private var tail = [Spring](repeating: Spring(), count: 3)
    private var flap = [[Spring]](repeating: [Spring(), Spring()], count: 2)
    private var sweep = [[Spring]](repeating: [Spring(), Spring()], count: 2)

    func update(turn: Float, nod: Float, mouthOpen: Float, time: Float, dt rawDt: Float) -> FinPose {
        let dt = min(rawDt, 0.1)
        var pose = FinPose()
        guard dt > 0 else { return pose }
        let k = 1 - exp(-dt * 18)
        turnRate += ((turn - (lastTurn ?? turn)) / dt - turnRate) * k
        nodRate += ((nod - (lastNod ?? nod)) / dt - nodRate) * k
        lastTurn = turn; lastNod = nod
        let energy = 0.6 + 1.2 * min(1, mouthOpen)
        let steps = max(1, Int((dt / (1.0 / 120)).rounded(.up)))
        let h = dt / Float(steps)

        // tail
        let tailTarget = simd_clamp(-turnRate * 0.35 * finReaction, -0.8, 0.8)
        for _ in 0..<steps {
            var target = tailTarget
            for i in tail.indices { tail[i].step(to: target, stiffness: 70, ratio: 0.32, h: h); target = tail[i].angle }
        }
        for i in tail.indices {
            pose.tail[i] = tail[i].angle + 0.1 * finSway * energy * sin(4.2 * time - 0.9 * Float(i))
        }

        // side fins: s = 0 left (+1), 1 right (-1)
        let flapTarget = simd_clamp(nodRate * 0.3 * finReaction, -0.6, 0.6)
        for s in 0..<2 {
            let side: Float = s == 0 ? 1 : -1
            let forward = simd_clamp(side * turnRate * 0.3 * finReaction, -0.6, 0.6)
            let sweepTarget = -side * forward
            for _ in 0..<steps {
                var tf = flapTarget, ts = sweepTarget
                for i in 0..<2 {
                    flap[s][i].step(to: tf, stiffness: 55, ratio: 0.35, h: h); tf = flap[s][i].angle
                    sweep[s][i].step(to: ts, stiffness: 55, ratio: 0.35, h: h); ts = sweep[s][i].angle
                }
            }
            let phase: Float = s == 0 ? 0 : 0.5
            for i in 0..<2 {
                let a = 5.6 * time + phase - 0.7 * Float(i)
                pose.pecFlap[s][i] = flap[s][i].angle + 0.14 * finSway * energy * sin(a)
                pose.pecSweep[s][i] = sweep[s][i].angle - side * 0.08 * finSway * energy * sin(a + 1.2)
            }
        }
        return pose
    }
}

// Applying it (rest = the joint's rest rotation, captured once at load):
// joint.rotation = rest * simd_quatf(angle: pose.tail[i], axis: [1, 0, 0])
// joint.rotation = rest * simd_quatf(angle: flap, axis: [1, 0, 0]) * simd_quatf(angle: sweep, axis: [0, 0, 1])
```

**Verify** on the device: driving `jointTransforms` of the skinned fin entities each frame, and that
joint order/names match the table in section 1.

## 4. Fin ripple (all four fins)

Each fin's `FinWave` UV set: **U** = 0 at the root (where the fin meets the body) -> 1 at the farthest
edge; **V** = position across the fan, 0..1. Per fin, from `fish.rig.json` -> `finWave.fins[<name>]`:

```
offset = axisUsd * amplitude * U^falloff * sin(2π * (U / wavelength - phase + V * cross))
phase += speed * finWaveSpeed * (1 + 0.6 * min(1, mouthOpen)) * dt     // per fin; accumulate
amplitude *= finWave
```

- Use **`axisUsd`** (the fin's sideways direction in its own mesh space, Blender/USD axes); `axis` is
  the same in glTF axes for the web app.
- `amplitude` is in mesh units at the outer edge; the Xform's scale applies on top.
- Accumulate `phase` instead of using `time * speed`, so changing the speed never makes the wave jump.

Current values (the artist tunes them in Blender; always re-read rig.json after an export):

| Fin | amplitude | wavelength | speed | falloff | cross | axisUsd |
| --- | --- | --- | --- | --- | --- | --- |
| Fin_Tail | 0.151 | 4.04 | 0.8 | 3.08 | 2.11 | (1, 0, 0) |
| Fin_Dorsal | 0.1498 | 4.04 | 0.8 | 3.08 | 2.11 | (0.0003, -0.0784, 0.9969) |
| Fin_Pectoral.L | 0.1266 | 4.04 | 0.8 | 3.08 | 2.11 | (-0.5769, 0.7816, -0.2373) |
| Fin_Pectoral.R | 0.1266 | 4.04 | 0.8 | 3.08 | 2.11 | (-0.5769, 0.7816, -0.2373) |

What it looks like: with these values the roots stay still and the edges move about 11-15 cm; the
whole fin bends in one long wave (wavelength 4 = four fin lengths) that ripples across the fan
(cross 2.1), and it livens up while the singer sings.

RealityKit sketch: one geometry modifier per fin with that fin's axis and cross as constants, the
per-frame values in `custom`:

```metal
#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
using namespace metal;

// custom: x = amplitude * finWave, y = wavelength, z = falloff, w = phase
[[visible]] void finWaveTail(realitykit::geometry_parameters params) {
    const float3 AXIS  = float3(1.0, 0.0, 0.0);   // fish.rig.json Fin_Tail.axisUsd
    const float  CROSS = 2.11;                     // fish.rig.json Fin_Tail.cross
    float4 c  = params.uniforms().custom_parameter();
    float2 fw = params.geometry().uv1();           // the FinWave UV set
    float  u  = clamp(fw.x, 0.0, 1.0);
    float  s  = sin(6.2831853 * (u / c.y - c.w + fw.y * CROSS));
    params.geometry().set_model_position_offset(AXIS * c.x * pow(u, c.z) * s);
}
```

```swift
// once per fin: wrap its material with the fin's modifier
let library = device.makeDefaultLibrary()!
var tailMaterial = try CustomMaterial(from: original,
                                      geometryModifier: .init(named: "finWaveTail", in: library))
// every frame: advance the phase, write back (materials are value types)
tailPhase += speed * finWaveSpeed * (1 + 0.6 * min(1, mouthOpen)) * dt
tailMaterial.custom.value = SIMD4<Float>(amplitude * finWave, wavelength, falloff, tailPhase)
tailModel.model?.materials = [tailMaterial]
```

**Verify** on the device:
- `uv1()` is the FinWave set: U should read 0 at the root. If V looks flipped, use `1 - fw.y`.
- whether the offset on the skinned fins is applied before skinning (the web app adds it before); if
  RealityKit applies it after, the ripple still works but in the fin's rest orientation.
- the fins render double-sided (they are thin sheets with thickness from the export).

## 5. Order per frame

1. Update Face Cap state, the head rest pose and the smoothed weights (`ios-handoff.md` section 4).
2. `turn`, `nod`, rates, `mouthOpen`, `energy` (section 2).
3. Springs and sway: tail, side fins (section 3); write the joints.
4. Ripple phases and material parameters (section 4).
5. Render.

## 6. Testing without a singer

- `node relay/replay.mjs --to <ipad-ip>:8080 --loop` replays a recorded take as live Face Cap data.
- Run the web app (`npm run relay`, `npm run dev`) with the same replay sent to `127.0.0.1:8080` and
  compare side by side. Its control panel has the same settings ("Fin reaction", "Swim motion",
  "Fin wave", "Fin wave speed").
- In Blender, each fin's "FinWave preview" modifier shows the ripple (press play); its values are
  what ends up in rig.json.

Checklist:
- [ ] turn the head quickly: the tail lags toward the turn, overshoots and settles; the inside side fin
      flares forward, the outside one tucks back
- [ ] nod: both side fins lift and wobble back as a mirror pair; their roots stay on the body
- [ ] at rest: tail sways, side fins scull, all four fins ripple; roots still, edges ~11-15 cm
- [ ] sing (mouth open): sway, sculling and ripple all get livelier
