# Facefish

A Three.js fish avatar driven by [Face Cap](https://www.bannaflak.com/face-cap/) live
mode (ARKit face tracking on an iPhone), packaged for iPad with Capacitor.

The show setup is two devices and a screen (see [Show setup](#show-setup-iphone--ipad--hdmi-screen)):

```
iPhone with Face ID (Face Cap)  ──OSC/UDP, Wi-Fi──▶  iPad app  ──HDMI──▶  screen inside the helmet
```

During development a Node relay sits in between, so the app also runs in any desktop
browser:

```
iPhone (Face Cap)  ──OSC/UDP──▶  relay (Mac/PC)  ──WebSocket──▶  browser / iPad app
```

Face Cap streams OSC over UDP. A web page (in a browser or in Capacitor's WebView)
can't open a UDP socket, so the relay forwards the raw datagrams over a WebSocket.
The app decodes OSC itself, so a native UDP receiver in the iPad app can replace the
relay without touching the rest of the code.

## Quick start

```sh
npm install

# 1. Relay: prints the IP / port to type into Face Cap and the ws:// URL for the app.
npm run relay
#    No iPhone handy? Generate synthetic tracking data instead:
npm run relay -- --fake

# 2. App in a desktop browser (also reachable from the iPad's Safari on the LAN).
npm run dev
```

Open the printed URL. Tap the canvas to hide or show the HUD; the HUD has a field for
the relay address, which is remembered. You can also pass it as `?ws=ws://<ip>:8765`.

In Face Cap: **Live Mode → OSC**, enter the relay machine's IP and the UDP port
(default `8080`). Face Cap and the relay machine must be on the same Wi-Fi. If nothing
arrives, it's almost always the firewall on the relay machine.

Relay ports can be changed: `npm run relay -- --udp 9000 --ws 9001`.

## iPad build (Capacitor)

```sh
npm run cap:sync      # builds the web app and copies it into ios/
npm run cap:open      # opens Xcode; run on the iPad from there
```

The app talks to the relay over plain `ws://`, so the iOS project needs two things
(already set in `ios/App/App/Info.plist`):

- `NSAppTransportSecurity` → `NSAllowsLocalNetworking = YES`
- `NSLocalNetworkUsageDescription`, so iOS shows the local-network permission prompt

On first launch, open the HUD and enter the relay address once.

## Control panel

Tap the button in the bottom-right corner (or press `p`) to open the control panel.
It has a button for every action, labelled with the keys that trigger it, and live
settings that are remembered on the device:

| Setting | What it does |
|---|---|
| Action strength | Amplitude of the body actions. `1.5` by default; `1` is the authored size. |
| Expression | Exaggerates the tracked face. `1.3` by default; `1` is as tracked. |
| Head turn | How much the fish turns with the head. `1` follows exactly. |
| Head move | How far the fish moves in the bowl when the head moves inside the helmet. About 5 cm of head travel per unit becomes a quarter of the fish's width. |
| Auto-center head | Slowly relearns the resting pose while tracking, so a shifted helmet doesn't leave the fish leaning. **Center head** (or `c`) sets it instantly. |
| Zoom, Vertical offset | Frame the fish in the porthole. |
| Caustics | Strength of the light ripples on the fish. `1.8` by default. |
| Water tint | Blue haze between the camera and the fish. `0.35` by default, `0` is clear. |
| Helmet walls | The inside of the helmet behind the fish, catching the caustics. Off shows open water instead. |
| Bubbles | Bubbles from the mouth while singing and from movement. `1` by default, `0` is off. |
| Mirror, Porthole mask, Face gestures, Idle actions, Status HUD | The same switches as the URL parameters below. |

Actions: **lap**, **spin**, **nod**, **wiggle**, **shake**, **bounce**, **dash**. Keys
`1`–`7` or `l s n w k b d`; clickers and pedals send Page Up/Down, arrows, Space and
Enter, which are mapped too. The same settings can be given as URL parameters
(`?strength=2&expr=1.5&caustics=2&bubbles=1.5&tint=0.5&head=1&move=1.5&mirror=1&zoom=1.1&y=0.1&porthole=1&hud=on`); add
`?reset` to go back to the defaults.

## Helmet interior

The walls behind the fish are the inside of the diving helmet: a sphere seen from
within, lit by the same projected caustics as the fish. The riveted brass is drawn
procedurally. To use a photo of the real helmet instead, put an equirectangular
image (2:1, the seam ends up behind the camera) at `public/textures/helmet.jpg`, or
pass `?helmet_tex=<url>` during development.

## Using a Blender model

Drop your exported model at `public/models/fish.glb` and the app uses it instead of
the procedural fish. Shape keys are matched to Face Cap blendshapes by name and a
`Head` node or bone gets the head rotation. See [blender/README.md](blender/README.md)
for naming, orientation and export settings, and run
`blender/add_facecap_shapekeys.py` inside Blender to create the 52 correctly named
shape keys on your mesh. During development you can also point at any file with
`?model=<url>`.

## Project layout

```
relay/relay.mjs          UDP → WebSocket relay, OSC action input, control page (+ --fake)
src/facecap/osc.ts       minimal OSC 1.0 decoder (messages + bundles)
src/facecap/decoder.ts   OSC messages → FaceFrame (52 weights, head, eyes)
src/facecap/blendshapes.ts  Face Cap blendshape index table
src/facecap/source.ts    FaceSource interface + WebSocket implementation
src/fish/mapping.ts      FaceFrame → FishPose: mirroring, smoothing, idle behaviour
src/fish/Fish.ts         procedural fish mesh (fallback when there is no model)
src/fish/GltfFish.ts     Blender/glTF fish: shape keys by name, Head/Jaw/Eye/Tail nodes
blender/                 Blender conventions and a shape-key setup script
src/scene.ts             renderer, camera, lights, ambient bubbles
src/water/               caustics texture, helmet interior, background shader, bubbles
src/actions/             ActionPlayer, procedural actions (lap, spin, nod, ...), key + gesture triggers
src/config.ts            URL/localStorage settings (mirror, head gain, framing, hud...)
src/ui/hud.ts            status overlay + relay URL form
src/ui/panel.ts          control panel: action buttons with their keys, live settings
src/main.ts              wires everything together
```

## Tuning

`src/fish/mapping.ts` has `DEFAULT_MAPPING`:

- `headSigns` flips head axes. Defaults mirror yaw and roll so the fish behaves like a
  mirror; flip a sign if the head turns the wrong way.
- `headGain`, `headLimitDeg` tame head motion.
- `rateFast` / `rateSlow` are smoothing rates; higher is snappier.
- `idleAfter` is how long without packets before the idle animation takes over.

## Show setup: iPhone → iPad → HDMI screen

```
iPhone with Face ID (Face Cap)  ──OSC/UDP, Wi-Fi──▶  iPad app  ──HDMI──▶  screen inside the helmet
```

- **iPhone with Face ID** runs Face Cap in Live Mode → OSC, looking at the singer's
  face. Face tracking needs the TrueDepth camera, so any Face ID iPhone works.
- **iPad** runs Facefish as a packaged app (Capacitor). It receives Face Cap's data
  directly, renders the fish, and takes show cues.
- **HDMI screen inside the helmet** shows the fish, fed from the iPad through a USB-C
  to HDMI adapter (Lightning Digital AV adapter on older iPads).

No laptop is needed during the show.

### Why it has to be a packaged app, not Safari

Face Cap only sends OSC over UDP, and no web page can receive UDP, in Safari or
anywhere else. With Safari on the iPad you would still need the relay running on a
laptop. The packaged app adds a small native UDP listener that passes Face Cap's raw
datagrams to the web code, which already decodes them. Packaging also gives:

- the web app bundled inside, so it runs offline; only the iPhone → iPad link uses the network
- full screen with no browser bar, and the screen kept awake (`AppDelegate.swift`)
- show cues on the same UDP port: OSC `/action lap` from QLab, TouchOSC or a show
  controller. A Bluetooth clicker or pedal pairs with the iPad as a keyboard and uses
  the existing key shortcuts.

### Status

| Part | State |
| --- | --- |
| Capacitor iOS project, `npm run cap:sync` / `cap:open`, local-network permission, keep-awake | Done |
| Relay (Mac/PC) for development and as a fallback | Done |
| Native UDP listener in the iPad app (Capacitor plugin, port `8080`), and a switch in the app between relay and direct UDP | To do |
| Fish full screen on the external display, control panel on the iPad | To do (plain mirroring works meanwhile) |
| Operator control page served by the iPad app (the relay serves it today) | Optional |

### The HDMI screen

- **Plain mirroring** works with no code: plug in the adapter and the iPad mirrors.
  The iPad's screen shape doesn't match a 16:9 display, so there are black bars, and
  anything on the iPad screen (control panel, HUD) also shows in the helmet. Keep the
  HUD hidden (`?hud=off`) and the panel closed during the show.
- **External display mode** (planned): the app puts the fish full screen on the HDMI
  display at its native resolution and aspect, while the iPad itself shows the control
  panel. This is a small native addition to the packaged app.

### The iPhone → iPad link

Latency here is what the audience notices. During development we measured a
1-second lag that turned out to be Apple's AirDrop radio (AWDL) interrupting Wi-Fi on
the Mac (fixed there with `sudo ifconfig awdl0 down`, which resets on reboot). iOS has
no such command, so:

- **Use a network you control:** a small dedicated router, or the iPhone's Personal
  Hotspot with the iPad joined to it. Venue Wi-Fi is congested and unpredictable.
- **Give the iPad a fixed IP** (a DHCP reservation on the router) and enter it in
  Face Cap with UDP port `8080`.
- **Turn off AirDrop, Handoff and AirPlay Receiver** on both devices.
- **Test inside the actual helmet**: it is metal and can weaken the signal.

### Developing and testing

- **Desktop browser:** `npm run relay` (or `npm run relay -- --fake`) and `npm run dev`,
  as in Quick start. This is still the fastest loop for look and mapping work.
- **iOS Simulator:** the Simulator uses the Mac's network, so Face Cap on the iPhone
  can send to the Mac's IP and the app in the Simulator receives it. This tests the
  native UDP path without the iPad.
- **iPad:** `npm run cap:sync`, then `npm run cap:open` and run from Xcode. A free Apple
  ID gives installs that expire after 7 days; the Apple Developer Program gives
  TestFlight and longer-lived installs for rehearsals and shows.

### Alternatives we considered

- **Face tracking in the browser** (MediaPipe Face Landmarker): runs in iPad Safari
  from the camera and outputs the same 52 blendshape names, so the mapping would work
  unchanged. It is less precise than Face Cap's depth camera, needs good light,
  pucker and funnel are weak and noisy, and `tongueOut` is always zero. A fallback if
  Face Cap can't be used.
- **A fully native iPad app** (ARKit + RealityKit, no web): the best data, but ARKit
  face tracking only uses the camera on the screen side, and the whole renderer
  (caustics, bubbles, helmet, tint) would need rewriting in Metal/RealityKit.
- **Face Cap on the iPad itself** next to the web app: iPadOS pauses whichever app
  isn't in front, so both would have to run side by side in Split View. Fragile.

### Settings for the helmet

The fish is the singer's face seen from the front, framed for the helmet window.
That changes a few defaults, all in `src/config.ts` and settable once via URL
parameters (they're remembered on the device):

| Parameter | Default | Meaning |
| --- | --- | --- |
| `mirror` | `0` | The fish is the singer's face seen from the front, so `_L` shapes land on the fish's own left. Use `mirror=1` for desk testing with the screen facing you. |
| `head` | `0` | Head rotation gain. The helmet physically turns with the head, so the virtual head stays still. Try `0.2` for a little extra life. |
| `zoom`, `y` | `1`, `0` | Framing for the porthole: camera zoom and vertical shift. |
| `porthole` | `0` | Dark circular mask for a round window. |
| `hud` | `auto` | `auto` hides the overlay a few seconds after tracking starts, `on`/`off` force it. Press `h` or tap to peek. |
| `gestures` | `0` | Let the singer trigger actions with held face gestures. |
| `idleActions` | `0` | Random actions while idling between songs. |
| `reset` | | Forget saved settings. |

Example first launch on the iPad while it still uses the relay:
`?ws=ws://10.0.0.2:8765&porthole=1&zoom=1.15&y=0.05`.

Also for the stage build:

- The native app keeps the screen awake (`AppDelegate.swift`). Use Guided Access to
  lock the iPad to the app, and turn brightness up on the HDMI screen.
- Pixel ratio is capped at 1.5 for thermal headroom. If the iPad sits somewhere
  without airflow and gets hot, lower it further in `src/scene.ts` or shrink the
  caustics texture.
- Network: see [The iPhone → iPad link](#the-iphone--ipad-link) above.

## Actions and how to trigger them

Actions are short body animations: `lap` (swim a loop out of frame and back),
`spin`, `nod`, `wiggle`. Face tracking keeps running underneath. Two kinds:

- **Procedural** (`src/actions/procedural.ts`): animate the avatar's root transform,
  so they work on the placeholder fish and on any Blender model.
- **Authored clips** from Blender: export NLA tracks in the GLB and name them like
  the action (`Lap`, `Spin`). When a clip with that name exists, it's used instead
  of the procedural one. Clips should animate a body/root bone, never the `Head`
  bone or shape keys, which tracking owns.

Nobody can touch the iPad inside the helmet, so triggers come from outside:

| Trigger | How | Needs |
| --- | --- | --- |
| Bluetooth clicker / pedal | Presentation clickers and page-turner pedals pair with the iPad as keyboards. Page Down / Enter → lap, Page Up → spin, arrows → nod / wiggle, or keys `1`–`4`. Map in `DEFAULT_KEYS`. | Nothing else. Test range inside the helmet. |
| Control page | `http://<relay>:8765/` on the operator's laptop or phone: big buttons, keyboard, and a MIDI controller via Web MIDI. | Relay running, same network (optional in the iPad app, see Status above). |
| OSC | `/action lap` or `/action/lap` to the relay's UDP port from QLab, Ableton, TouchOSC, a show controller. | Relay running today; the iPad app's own UDP port once the native listener is in. |
| Face gestures | `?gestures=1`: tongue out held → wiggle, wide eyes + brows up → spin, long left wink → lap. Held for a moment, with a cooldown. | Nothing, the singer does it. |
| Idle | `?idleActions=1`: random actions when no tracking, between songs. | Nothing. |

Any WebSocket client can also send `{"type":"action","name":"lap"}` to the relay.

## Underwater look

`src/water/CausticsTexture.ts` renders an animated caustics pattern into a texture
every frame. A spot light above the fish projects it (`SpotLight.map`) onto whatever
is in the scene, so it lands on the procedural fish and on a Blender model alike. The
same texture feeds the background shader in `src/water/Background.ts` for surface
shimmer, alongside the depth gradient and light shafts. Tune `tiles` and
`brightness` on the caustics material, and the spot light intensity in
`src/scene.ts`, to taste.

## Notes for a singer

Face Cap tracks singing well, but a few things matter more than for casual use:

- **Latency.** The relay adds well under a frame; smoothing adds a little. Jaw and
  mouth use the fast rate in `DEFAULT_MAPPING` so lips stay on the beat. If it feels
  late, raise `rateFast`.
- **Mouth shapes.** `mouthClose` (lips together with the jaw down) pulls the visible
  opening back so humming doesn't look like shouting, and `mouthStretch` widens the
  corners for "ee" vowels. A Blender model gets these from its shape keys; see
  `blender/README.md`.
- **Big head moves.** The head limit is 55 degrees. If a performer turns further and
  you want the fish to follow, raise `headLimitDeg`.
- **Mic and mounting.** ARKit copes with a handheld mic, but a headset boom across the
  mouth can degrade jaw tracking. Mount the iPhone on the mic stand at face height so
  the phone doesn't move with the performer.
- **Wi-Fi at a venue.** Congested Wi-Fi drops packets. Use a dedicated router or the
  iPhone's Personal Hotspot; see [The iPhone → iPad link](#the-iphone--ipad-link).
- **The "oo" vowel.** For "oo", Face Cap reports a high `mouthPucker` plus some
  `jawOpen` (the real jaw drops a little) and often some `mouthFunnel`. The shapes add
  up, so a big jawOpen makes "oo" open too far. Sculpt the pucker with jawOpen at about
  `0.25` showing (Blender's "shape key edit mode" button shows the mix while you edit),
  or lower the Expression setting. A pucker-damps-jaw setting in the app is a possible
  addition.
- **Idle.** After 1.5 s without packets the fish idles. Between songs this is what
  you see; set `idleAfter` longer if tracking is briefly lost when the singer turns
  away.

## Face Cap protocol reference

| Address | Args | Meaning |
| --- | --- | --- |
| `/W` | int index, float value | one blendshape weight (index table in `blendshapes.ts`) |
| `/HT` | 3 floats | head position |
| `/HR` | 3 floats | head rotation, Euler degrees |
| `/HRQ` | 4 floats | head rotation, quaternion |
| `/ELR`, `/ERR` | 2 floats | left / right eye rotation |
