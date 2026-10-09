import ARKit
import Foundation
import simd

/// What the fish does while it waits for a face: it looks around the bowl (the eyes dart to a new
/// spot every second or two, the head follows more slowly), blinks now and then, and every few
/// seconds puffs its cheeks, turns toward one of the bottom corners and blows a stream of bubbles
/// through puckered lips.
///
/// Angles are in the avatar root's frame: +yaw turns toward the fish's left (screen right), +pitch
/// tips the nose down.
struct IdleLife {
    struct Frame {
        /// The whole fish's turn (radians).
        var yaw: Float = 0
        var pitch: Float = 0
        var roll: Float = 0
        /// Where the eyes look, relative to the head (radians).
        var eyeYaw: Float = 0
        var eyePitch: Float = 0
        var blink: Float = 0
        var cheekPuff: Float = 0
        var pucker: Float = 0
        /// Bubbles per second out of the mouth.
        var bubbles: Float = 0

        /// The frame as ARKit blend shapes on the fish's own sides, for the eye, lid and face rigs.
        /// `eyeRange` is the eyes' full turn (EyeRig.range).
        func weight(_ location: ARFaceAnchor.BlendShapeLocation, eyeRange: Float) -> Float {
            let towardLeft = max(0, eyeYaw) / eyeRange, towardRight = max(0, -eyeYaw) / eyeRange
            let down = max(0, eyePitch) / eyeRange, up = max(0, -eyePitch) / eyeRange
            switch location {
            case .eyeLookOutLeft, .eyeLookInRight: return towardLeft
            case .eyeLookInLeft, .eyeLookOutRight: return towardRight
            case .eyeLookDownLeft, .eyeLookDownRight: return down
            case .eyeLookUpLeft, .eyeLookUpRight: return up
            case .eyeBlinkLeft, .eyeBlinkRight: return blink
            case .cheekPuff: return cheekPuff
            case .mouthPucker: return pucker
            default: return 0
            }
        }
    }

    private var time: Float = 0
    private var gaze = SIMD2<Float>(repeating: 0)
    private var head = SIMD2<Float>(repeating: 0)
    private var nextGlance: Float = 0.5
    private var nextBlink: Float = 1.5
    private var nextBlow: Float = 3
    private var blowStart: Float?
    private var blowSide: Float = 1

    /// `waiting`: no face right now (new looks and blows only start then). `weight`: how much of the
    /// idle shows (0 resets it, so it starts fresh next time).
    mutating func update(deltaTime: Float, waiting: Bool, weight: Float) -> Frame {
        guard weight > 0 else {
            self = IdleLife()
            return Frame()
        }
        time += deltaTime
        var frame = Frame()

        // Looking around: the eyes jump to a new spot, the head turns most of the way after them.
        if waiting, time >= nextGlance {
            gaze = [Float.random(in: -0.6...0.6), Float.random(in: -0.3...0.25)]
            nextGlance = time + Float.random(in: 0.8...2.5)
        }
        head += (gaze * 0.7 - head) * (1 - exp(-deltaTime / 0.6))

        // Blinks now and then.
        if waiting, time >= nextBlink + 0.18 {
            nextBlink = time + Float.random(in: 2.5...5)
        }
        if time >= nextBlink, time < nextBlink + 0.18 {
            frame.blink = sin(.pi * (time - nextBlink) / 0.18)
        }

        // Blowing bubbles: turn toward a bottom corner and fill the cheeks, then pucker and let the
        // air out as a stream of bubbles, then turn back.
        if waiting, blowStart == nil, time >= nextBlow {
            blowStart = time
            blowSide = Bool.random() ? 1 : -1
        }
        var corner: Float = 0
        if let start = blowStart {
            let b = time - start
            corner = Self.smoothstep(Self.ramp(b, 0, 0.6)) * (1 - Self.smoothstep(Self.ramp(b, 2.6, 3.3)))
            frame.cheekPuff = Self.smoothstep(Self.ramp(b, 0.15, 0.7)) * (1 - Self.smoothstep(Self.ramp(b, 1.1, 2.2)))
            frame.pucker = 0.9 * Self.smoothstep(Self.ramp(b, 0.9, 1.1)) * (1 - Self.smoothstep(Self.ramp(b, 2.3, 2.6)))
            frame.bubbles = b > 1.05 && b < 2.3 ? 10 + 30 * (1 - Self.ramp(b, 1.05, 2.3)) : 0
            if b > 3.3 {
                blowStart = nil
                nextBlow = time + Float.random(in: 4...8)
            }
        }

        // The head: looking around, or turned to the corner (the eyes follow the bubbles).
        let cornerTurn = SIMD2<Float>(0.45 * blowSide, 0.3)
        let headTurn = head * (1 - corner) + cornerTurn * corner
        let eyes = (gaze - head) * (1 - corner) + SIMD2(0.1 * blowSide, 0.15) * corner
        frame.yaw = headTurn.x
        frame.pitch = headTurn.y
        frame.roll = -0.1 * blowSide * corner
        frame.eyeYaw = eyes.x
        frame.eyePitch = eyes.y
        return frame
    }

    private static func ramp(_ x: Float, _ from: Float, _ to: Float) -> Float {
        min(max((x - from) / (to - from), 0), 1)
    }

    private static func smoothstep(_ x: Float) -> Float { x * x * (3 - 2 * x) }
}
