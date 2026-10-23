# Facefish

Facefish is an iOS app that uses ARKit face tracking and RealityKit to drive an
animated fish avatar. The avatar appears in an underwater scene with animated
lighting, caustics, and bubbles.

## Requirements

- iOS 18 or later
- An iPhone or iPad with a TrueDepth (Face ID) camera for face tracking
- Xcode to build and run the app
- An external display is optional

Face tracking is not available in the simulator or on devices without a
TrueDepth camera.

## Build and run

1. Open `ARFace.xcodeproj` in Xcode.
2. Select the `ARFace` scheme and a compatible iPhone or iPad.
3. Build and run the app, then allow camera access when prompted.

The project uses the local Swift package at `Packages/RealityKitContent` for its
underwater scene. Keep this package with the project; no download is required.
If Xcode reports **Missing package product 'RealityKitContent'**, verify that
`Packages/RealityKitContent/Package.swift` exists, then use **File > Packages >
Resolve Package Versions** and rebuild.

## Using the app

The live face-tracked avatar is mirrored by default. Use **Mirror** to switch
between reflected and direct movement. The avatar follows head orientation and
facial expressions, including mouth and jaw movement. Its tail and pectoral fins
respond to head turns and nods with damped motion, while a gentle swimming sway
continues at rest. Opening the mouth makes the swimming more energetic and emits
a randomized burst of 7-11 bubbles over roughly half a second from the center of
the mouth, mostly small bubbles with one or two larger ones. They spread outward with
a fast forward launch in the fish's facing direction, slow down, and float upward
with turbulent drift independently of subsequent head movement. Mouth bubbles
keep their full size until they disappear.
Close and reopen the mouth to emit another burst. If tracking is lost, the fins
transition to an idle sway.

### Phone orientation

Open **Settings** (the sliders button), then **General > Phone orientation**.
**Automatic** is the default: it detects upright or upside-down portrait mounting
using gravity and keeps the fish upright without changing facial expressions or
Mirror behavior. When the phone is flat or sideways, it holds the last detected
orientation rather than flipping unpredictably. Before the first sensor reading,
it assumes upright.

Choose **Upright** or **Upside down** to lock the mounting orientation manually.
The choice is saved between launches and applies to face tracking on both the
phone and external display, the debug camera preview, and water motion. On the
phone, the entire avatar canvas rotates together: fish, underwater background,
water, bubbles, loading/error content, and tracking overlays. Settings and action
icons stay fixed at the bottom of the phone and do not rotate. This is an in-app
rotation, so it also works on devices that do not support upside-down system
orientation and with system orientation lock enabled. Orientation detection runs
without a tracked face and pauses while the app is inactive. The external display
stays upright independently of the phone's mounting unless its separate
**External display upside down** toggle is enabled. Settings sheets and the
Bluetooth controller retain their normal system orientation. The Bluetooth
controller's **Settings** tab can change the main phone's orientation setting,
including through **Send all settings**.

To check orientation detection and pose/motion correction on a Mac, run:

```sh
swiftc ARFace/Tracking/PhoneOrientation.swift Tests/PhoneOrientationChecks.swift -o /tmp/PhoneOrientationChecks
/tmp/PhoneOrientationChecks
swiftc ARFace/Views/CanvasOrientationEffect.swift Tests/PhoneCanvasRenderingChecks.swift -o /tmp/PhoneCanvasRenderingChecks
/tmp/PhoneCanvasRenderingChecks
```

The canvas rendering check verifies actual square, portrait, and landscape SwiftUI
renders, including the background, avatar placeholder, and overlays, in both
mounting orientations at 1x, 2x, and 3x scales.

On a TrueDepth device, check both portrait mountings in Automatic and manual
modes, including head turns, nods, tilts, Mirror on/off, the camera preview,
water motion, and external-display output. Verify that the entire phone background
turns with the fish, including with system orientation lock enabled, while tracking
is lost, and after backgrounding/foregrounding. Check that the setting survives
relaunch and can be changed from the Bluetooth controller. Repeat on iPhone and iPad.

### Audio-reactive bubbles (proof of concept)

The app also listens to the microphone (allow microphone access when prompted;
audio is analyzed live and never recorded). `ARFace/Audio/AudioLevelMonitor.swift`
measures the overall level and three frequency bands — low (20–250 Hz), mid
(250–2,000 Hz), and high (2,000–10,000 Hz) — each normalized to 0–1 between
-60 and -10 dBFS and smoothed. The levels are logged about four times a second
at debug level under the `ARFace` subsystem, `Audio` category (stream them with
Console or `log stream --level debug --predicate 'category == "Audio"'`).

- Strong lows (above 0.6) while the mouth is open (above 0.3) release a stream of
  big bubbles from the mouth; louder lows stream faster.
- Strong highs (above 0.45) release a stream of small bubbles from the mouth.

Thresholds are defined in `ARFace/Avatar/AvatarController.swift`.

The underwater scene also includes rising ambient bubbles with the same buoyancy,
drag, and turbulent drift as mouth bubbles, animated spotlights,
shadows, and caustic lighting. On iOS 26 and later, bubbles are rendered as glass
spheres in a Metal post-processing pass. This traces both refractive interfaces
and samples the actual rendered scene, so the fish and lighting behind bubbles
are visibly distorted. Refraction displacement is reduced to 25% strength for a
subtler glass effect, without reducing reflections or highlights.
Scene depth keeps bubbles behind foreground objects.
Soft reflections, a broad upper highlight from the bright water surface, and
bright specular highlights are composited directly, independent of
scene lighting. This is screen-space refraction: off-screen objects and recursive
refraction through overlapping bubbles are not available.
On iOS 18-25, transparent sphere materials provide reflections and highlights
without scene refraction. The same fallback is used, with an error logged, if the
glass compute pipeline cannot be created.
Rendering updates and debug animation playback
stop when an avatar view is removed.

## Bluetooth control

The app starts in **main** mode and does not need a Bluetooth connection to
animate the avatar. Tap **Control** to open Bluetooth settings and the received
command log. Turn on **Control mode** to use this device as a remote instead;
face tracking and avatar rendering are paused on the controller. A controller
does not need a TrueDepth camera.

1. On the main device, tap **Control > Allow pairing**.
2. On the second device, turn on **Control mode**, tap **Find main app**, and
   select the main device from the nearby list. The short device identifier
   distinguishes devices with the same name.
3. Allow Bluetooth access on both devices and accept the iOS Bluetooth pairing
   prompt if shown. Commands become available once the encrypted connection
   and Facefish handshake finish.
4. Use the **Actions** tab to trigger **Swim a lap**, **Spin**, **Loop**, or
   **Blush** on the main avatar. The connection screen also provides **Ping**,
   **Mirror on**, and **Mirror off**; Ping only creates a log entry, while the
   Mirror commands update the main avatar, including on an external display.
   Successful delivery means the main app acknowledged the command.
5. The main app's **Received commands** section shows the latest 100 commands,
   newest first, with receipt times and a **Clear log** button.

Pairing is opt-in on the main device and accepts one controller at a time.
Only enable it near the controller you intend to use: the first encrypted
subscriber is accepted, without a separate in-app identity confirmation.
The custom BLE service uses an encrypted read/write command characteristic and
an encrypted notification subscription to track the connection. Commands use a
versioned JSON envelope and an allowlist; unknown or oversized messages are
rejected. This is a foreground-only scaffold, not a background remote service.
Keep both apps open; backgrounding either app, changing mode, or tapping
**Disconnect** ends the app connection. Pair again to reconnect. iOS may retain
the system Bluetooth bond, so subsequent connections may not show a pairing
prompt. Mode and command logs are not persisted across launches.

To check on two physical iOS devices, verify pairing, all three commands, main
log ordering/clearing, disconnect/reconnect, role changes, Bluetooth-off and
permission-denied states, and background/foreground transitions. Confirm that
the main avatar still works before pairing and after losing the controller,
and that a device without TrueDepth can access controller mode. BLE cannot be
validated using the simulator alone.

## Glass rendering checks

On a Metal-capable Mac, run `xcrun swift Tests/GlassBubbleRenderingChecks.swift`.
The checks execute the production shader on the GPU against a patterned scene
and verify background distortion, bright highlights, foreground occlusion,
unchanged pixels outside the bubble, and conventional and reversed-Z depth.
No camera or face-tracking device is required for these checks.

## External display

If the external panel is mounted upside down, enable **Settings > External display >
External display upside down** on the phone. This rotates the complete external
image by 180 degrees, including the fish, underwater background, water, bubbles,
and loading content. It does not change the phone's canvas, controls, or
face-tracking orientation. The toggle defaults to off, is saved between launches,
and can be set before connecting a display. It also appears in the Bluetooth
controller's **Settings** tab and is included in **Send all settings**.
The panel's physical mounting cannot be detected automatically from the phone.
Phone orientation and external display orientation are separate controls: either
device, or both, can be upside down. The external display section is always
available, even before a display is connected; diagnostics appear when connected.
The phone's settings button remains available while loading and while an external
display is connected.

With a physical display connected, verify both toggle positions for each phone
mounting, check that background and fish turn together without moving phone
controls, and confirm the choice survives disconnect/reconnect and app relaunch.

When an external display connects, the app attempts to select a square display
mode, preferring 1080 × 1080 or the available square mode closest to that size.
If no square mode is available, it leaves the current mode unchanged. The avatar
is rendered in a square canvas fitted to the external scene; the phone shows a
connection screen instead of rendering a second avatar. Face tracking and the
phone's Mirror and Debug controls remain available. The phone resumes avatar
rendering automatically when the external display disconnects.

## Debug inspector

Turn on **Debug** on the phone to open the inspector. It appears as a trailing
column on iPad or a resizable sheet on iPhone, with a small live camera preview
in the top-trailing corner. The inspector's collapsible sections remember their
expanded state between launches:

- **Tracking** shows tracking status or errors and the most active blend shapes.
  Adjust how many blend shapes are listed with the stepper.
- **Avatar** reports where the avatar is rendered, how many blend-shape targets
  were bound, and the applied `jawOpen` value.
- **Audio** shows microphone status and live overall, low, mid, and high levels;
  the low and high meters turn orange above their bubble thresholds.
- **Rendering** reports frame rate and includes a **Camera Z** slider to adjust
  the virtual camera's distance from 0.10 to 3.00 meters (default: 0.75 meters),
  including when the avatar is rendered on an external display. It provides switches for caustics, ambient,
  mouth, and audio bubbles, animated spotlights, directional shadows, blend shapes,
  and fin animation.
- **Animations** lets you filter the avatar's animations, play one once, loop it,
  or stop all animations. When connected to an external display, these controls
  operate on the externally rendered avatar.
- **External display** always provides the independent upside-down toggle.
  While connected, expand **Display diagnostics** for screen and scene
  geometry, native dimensions and aspect ratio, display scales, refresh rate,
  current, available, and preferred modes, and overscan settings. Choose an
  available resolution with the picker or use **Auto-select square (1080x1080)**.

Display diagnostics are reported by iOS and cannot identify a panel's physical
aspect ratio or any stretching, cropping, or letterboxing done by the panel or
adapter. The resolution picker and auto-select button can change the display
mode; the other diagnostics are informational.

## Fish asset

`ARFace/Resources/fish.usdz` is exported from the Blender file with `tools/save-export-copy.py`
(run inside Blender) and `tools/export-fish.sh`; see [docs/fish-export.md](docs/fish-export.md)
for the steps and the parts the app expects.

The fin rig uses the tail, pectoral and dorsal joints in `fish.usdz` and applies UV-mapped
waves to the tail, dorsal, and pectoral fins. Keep the expected joint names
(`Tail_1`–`Tail_3`, `Pec_L_0`–`Pec_L_2`, `Pec_R_0`–`Pec_R_2`, and `Dorsal_0`–`Dorsal_3`) and the
`FinWave` second UV set when replacing or editing the model. Eyelid meshes are
excluded from general blink blend-shape binding and custom material overrides.
Fin reaction, swim, ripple-height, and ripple-speed defaults are defined in
`ARFace/Avatar/FinRig.swift`.
