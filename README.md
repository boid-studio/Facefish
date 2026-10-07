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
a small bubble burst. If tracking is lost, the fins transition to an idle sway.

The underwater scene also includes rising ambient bubbles, animated spotlights,
shadows, and caustic lighting. Rendering updates and debug animation playback
stop when an avatar view is removed.

## External display

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
- **Rendering** reports frame rate and provides switches for caustics, ambient
  and mouth bubbles, animated spotlights, directional shadows, blend shapes,
  and fin animation.
- **Animations** lets you filter the avatar's animations, play one once, loop it,
  or stop all animations. When connected to an external display, these controls
  operate on the externally rendered avatar.
- **External display**, shown only while connected, reports screen and scene
  geometry, native dimensions and aspect ratio, display scales, refresh rate,
  current, available, and preferred modes, and overscan settings. Choose an
  available resolution with the picker or use **Auto-select square (1080x1080)**.

Display diagnostics are reported by iOS and cannot identify a panel's physical
aspect ratio or any stretching, cropping, or letterboxing done by the panel or
adapter. The resolution picker and auto-select button can change the display
mode; the other diagnostics are informational.

## Fish asset

The fin rig uses the tail and pectoral joints in `fish.usdz` and applies UV-mapped
waves to the tail, dorsal, and pectoral fins. Keep the expected joint names
(`Tail_1`–`Tail_3`, `Pec_L_1`–`Pec_L_2`, and `Pec_R_1`–`Pec_R_2`) and the
`FinWave` second UV set when replacing or editing the model. Eyelid meshes are
excluded from general blink blend-shape binding and custom material overrides.
Fin reaction, swim, ripple-height, and ripple-speed defaults are defined in
`ARFace/Avatar/FinRig.swift`.
