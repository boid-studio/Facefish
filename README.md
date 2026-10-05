# Facefish

Facefish is a project that involves facial recognition and augmented reality features using RealityKit. This repository contains the necessary code and resources to build and run the application on iOS devices.

## Square external display output

The external avatar uses a square canvas sized to the external window's height,
then stretches horizontally to fill the negotiated output. For a 1920 x 1200
output, this is a 1200 x 1200 canvas with a 1.6x horizontal pre-stretch, compensating
for a square panel that squeezes the entire incoming image to fit.

This compensation applies to all external displays; it assumes a square panel
with full-image stretching, not cropping or letterboxing. It adapts to window
size changes and does not change the HDMI signal resolution.

While an external display is connected, the phone shows a lightweight connection
screen instead of rendering a second 3D scene. Face tracking, Mirror/Debug controls,
tracking status, camera preview, and display diagnostics remain available on the
phone. The phone's avatar rendering resumes automatically on disconnect.
Scene update subscriptions and debug animations are stopped when an avatar view
is removed. External rendering quality and square compensation are unchanged.

## Debug inspector

Enable **Debug** on the phone to open the debug inspector: a trailing column on
iPad, or a resizable sheet on iPhone. While debug is on, a small camera preview
floats in the top-trailing corner. The inspector has collapsible sections, and
their expanded state is remembered between launches:

- **Tracking**: tracking status/errors and the top N blend shapes (N adjustable).
- **Avatar**: where the avatar is rendered, bound blend-shape targets, applied jawOpen.
- **Animations**: filter, play once, loop, and stop all avatar animations. When an
  external display is connected, this drives the avatar on that display.
- **External display** (only while connected): screen and scene dimensions,
  native pixel dimensions and aspect ratio, display scales, square canvas size and
  horizontal pre-stretch, maximum refresh rate, current/preferred/available modes,
  and overscan settings, refreshed once per second.

Collapsed sections stop refreshing. The external display always shows only the
avatar, without debug UI.

These values are reported by iOS; they do not reveal the panel's physical aspect
ratio or any stretching/cropping performed by the display or HDMI adapter.
Diagnostics do not change the output mode or avatar layout.

## Fish fin motion

The fish's tail and pectoral bones react to head turns and nods with damped,
chained springs; gentle swimming continues at rest and becomes livelier as the
mouth opens. If face tracking is lost, the fins transition to a small idle sway
after 1.5 seconds. All four fins also receive a UV-mapped ripple in the Metal
geometry modifier, layered with the existing caustic surface shader.

The rig expects the `Tail_1`–`Tail_3` and `Pec_L_1`–`Pec_L_2` /
`Pec_R_1`–`Pec_R_2` joint names and the `FinWave` second UV set in
`fish.usdz`. Ripple tuning and the default reaction, swim, ripple-height, and
ripple-speed values are defined in `FinRig.swift`.