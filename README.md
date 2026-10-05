# Facefish

Facefish is a project that involves facial recognition and augmented reality features using RealityKit. This repository contains the necessary code and resources to build and run the application on iOS devices.

## Square external display output

The external avatar uses a square canvas sized to the external window's height,
then stretches horizontally to fill the negotiated output. For a 1920 x 1200
output, this is a 1200 x 1200 canvas with a 1.6x horizontal pre-stretch, compensating
for a square panel that squeezes the entire incoming image to fit.

This compensation applies to all external displays; it assumes a square panel
with full-image stretching, not cropping or letterboxing. It adapts to window
size changes and does not change the HDMI signal resolution or the phone view.

## External display diagnostics

When an external display is connected, enable **Debug** on the phone to show
display diagnostics on the phone's main display, above the controls. The scrollable
panel refreshes once per second
and shows screen and scene dimensions, native pixel dimensions and aspect ratio,
display scales, square canvas size and horizontal pre-stretch, maximum refresh
rate, current/preferred/available modes, and
overscan settings. Disable **Debug** or disconnect the display to hide it.
The connected display continues showing only the avatar, without debug overlays.

These values are reported by iOS; they do not reveal the panel's physical aspect
ratio or any stretching/cropping performed by the display or HDMI adapter.
Diagnostics do not change the output mode or avatar layout.