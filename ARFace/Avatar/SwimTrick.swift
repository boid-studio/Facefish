import Foundation
import simd

/// The fish's quick moves, short enough for the middle of a sentence: a spin on the spot with a
/// hop, a vertical loop, a blush behind its fins, and blowing a stream of bubbles. They are layered on the live (tracked) pose, so the face keeps going,
/// and each one ends exactly where it began.
///
/// Like a real fish, it works the fins first (a wind-up against the move), then the body goes.
/// Works in the fish's own frame: +Z forward (toward the camera at rest), +Y up, +X its left.
struct SwimTrick {
    enum Kind { case spin, loop, blush, bubbles }

    /// What the move contributes this frame.
    struct Pose {
        /// Turn of the whole fish on top of the live pose, in its own frame.
        var rotation: simd_quatf
        /// Move of the whole fish (metres), in its own frame.
        var offset: SIMD3<Float>
        /// Turned so far about its up axis and its side axis (radians), for the fins to react to.
        var yaw: Float
        var pitch: Float
        /// 0...1, how hard the fins and tail work.
        var effort: Float
        /// -1...1, the turn that's coming (+ toward the fish's left): the fins steer first.
        var steer: Float
        /// The body wave (mesh units at the tail).
        var bend: Float
        /// Side fins over the eyes (fish's left, right), 0...1.
        var cover = SIMD2<Float>(repeating: 0)
        /// Rosy cheeks, 0...1.
        var blush: Float = 0
        /// The mouth taken over (0...1) for puffed cheeks and puckered lips, and bubbles per second.
        var mouthTakeover: Float = 0
        var cheekPuff: Float = 0
        var pucker: Float = 0
        var bubbles: Float = 0
    }

    let kind: Kind
    let duration: Float
    /// +1 spins toward the fish's left, -1 toward its right.
    private let direction: Float
    private var elapsed: Float = 0
    /// The spin's turn (radians) and speed: a spring pulled round, so it carries past and settles back.
    private var spinAngle: Float = 0
    private var spinSpeed: Float = 0

    init(kind: Kind, direction: Float) {
        self.kind = kind
        self.direction = direction
        switch kind {
        case .spin: duration = Float.random(in: 1.0...1.2)
        case .loop: duration = Float.random(in: 1.3...1.5)
        case .blush: duration = 3.0
        case .bubbles: duration = BubbleBlow.duration
        }
    }

    mutating func update(deltaTime: Float) -> Pose? {
        elapsed += deltaTime
        guard elapsed < duration else { return nil }
        let u = elapsed / duration
        switch kind {
        case .spin: return spin(u, deltaTime: deltaTime)
        case .loop: return loop(u)
        case .blush: return blush(elapsed)
        case .bubbles: return blowBubbles(elapsed)
        }
    }

    /// A full turn on the spot: a little turn and dip the other way, then the fins kick it round
    /// with a hop. It carries on about 20 degrees past the front and eases back, leaning into the
    /// turn while it's fast, nose up while in the air.
    private mutating func spin(_ u: Float, deltaTime: Float) -> Pose {
        // The fins pull a spring round a full turn; it lags, overshoots and settles (12 rad/s, damping 0.6).
        let pull = 2 * .pi * Self.smoothstep(Self.ramp(u, 0.1, 0.45))
        let steps = max(1, Int((deltaTime * 240).rounded(.up)))
        let step = deltaTime / Float(steps)
        for _ in 0..<steps {
            spinSpeed += (144 * (pull - spinAngle) - 14.4 * spinSpeed) * step
            spinAngle += spinSpeed * step
        }
        // Lands exactly on a full turn at the end.
        let turn = spinAngle + (2 * .pi - spinAngle) * Self.smoothstep(Self.ramp(u, 0.85, 1))
        let windUp = sin(.pi * Self.ramp(u, 0, 0.35))
        let yaw = direction * (turn - 0.3 * windUp)
        let fast = min(max(spinSpeed / 20, -1), 1)
        let v = Self.ramp(u, 0.12, 0.92)
        let pitch = -0.2 * sin(.pi * v)
        let roll = -direction * 0.4 * fast
        let hop = 0.035 * pow(sin(.pi * v), 2) - 0.008 * sin(.pi * Self.ramp(u, 0, 0.2))
        let effort = Self.effort(u)
        return Pose(
            rotation: simd_quatf(angle: yaw, axis: [0, 1, 0])
                * simd_quatf(angle: pitch, axis: [1, 0, 0])
                * simd_quatf(angle: roll, axis: [0, 0, 1]),
            offset: [0, hop, 0],
            yaw: yaw, pitch: pitch, effort: effort,
            steer: direction * sin(.pi * Self.ramp(u, 0, 0.45)),
            bend: 0.13 * effort
        )
    }

    /// A loop-the-loop: nose dips, then up and toward the camera, over the top upside down and
    /// back down to its spot.
    private func loop(_ u: Float) -> Pose {
        let v = Self.ramp(u, 0.12, 0.95)
        let angle = 2 * .pi * Self.smoothstep(v)          // nose up, around the loop
        let pitch = -angle + 0.25 * sin(.pi * Self.ramp(u, 0, 0.3))   // + is nose down
        let roll = direction * 0.15 * sin(.pi * v)
        let radius: Float = 0.065
        let offset = radius * SIMD3<Float>(0, 1 - cos(angle), sin(angle))
            - SIMD3<Float>(0, 0.01 * sin(.pi * Self.ramp(u, 0, 0.2)), 0)
        let effort = Self.effort(u)
        return Pose(
            rotation: simd_quatf(angle: pitch, axis: [1, 0, 0]) * simd_quatf(angle: roll, axis: [0, 0, 1]),
            offset: offset,
            yaw: 0, pitch: pitch, effort: effort,
            steer: 0,
            bend: 0.11 * effort
        )
    }

    /// Shy: the side fins come up over the eyes, the cheeks go rosy, the head dips and turns away
    /// with a little wiggle, one fin lowers for a peek, then the fins come down; the blush lingers.
    /// `t` is seconds (3 in all).
    private func blush(_ t: Float) -> Pose {
        let shy = Self.smoothstep(Self.ramp(t, 0, 0.4)) * (1 - Self.smoothstep(Self.ramp(t, 2.1, 2.7)))
        let covered = Self.smoothstep(Self.ramp(t, 0.05, 0.45)) * (1 - Self.smoothstep(Self.ramp(t, 2.2, 2.65)))
        let peek = pow(sin(.pi * Self.ramp(t, 1.05, 1.65)), 2)
        // The fin on the side it turns away from lowers a little for the peek.
        let peekCover = covered * (1 - 0.45 * peek)
        let cover = direction > 0 ? SIMD2(covered, peekCover) : SIMD2(peekCover, covered)
        let rosy = Self.smoothstep(Self.ramp(t, 0.15, 0.8)) * (1 - Self.smoothstep(Self.ramp(t, 2.2, 3.0)))
        let wiggle = 0.05 * sin(2 * .pi * 2.2 * t) * Self.smoothstep(Self.ramp(t, 0.3, 0.6)) * (1 - Self.smoothstep(Self.ramp(t, 1.0, 1.3)))
        let yaw = direction * (0.2 * shy - 0.12 * peek) + wiggle * shy
        let pitch = 0.18 * shy - 0.06 * peek                   // + is nose down
        let roll = -direction * 0.1 * shy
        return Pose(
            rotation: simd_quatf(angle: yaw, axis: [0, 1, 0])
                * simd_quatf(angle: pitch, axis: [1, 0, 0])
                * simd_quatf(angle: roll, axis: [0, 0, 1]),
            offset: SIMD3<Float>(0, -0.008, -0.012) * shy,
            yaw: yaw, pitch: pitch, effort: 0.15 * shy,
            steer: 0,
            bend: 0.02 * shy,
            cover: cover,
            blush: rosy
        )
    }

    /// Turns toward a bottom corner (on the `direction` side), puffs the cheeks and blows a stream
    /// of bubbles through puckered lips (BubbleBlow). `t` is seconds.
    private func blowBubbles(_ t: Float) -> Pose {
        let blow = BubbleBlow.at(t)
        let yaw = direction * BubbleBlow.cornerYaw * blow.corner
        let pitch = BubbleBlow.cornerPitch * blow.corner
        return Pose(
            rotation: simd_quatf(angle: yaw, axis: [0, 1, 0])
                * simd_quatf(angle: pitch, axis: [1, 0, 0])
                * simd_quatf(angle: direction * BubbleBlow.cornerRoll * blow.corner, axis: [0, 0, 1]),
            offset: .zero,
            yaw: yaw, pitch: pitch, effort: 0.1 * blow.corner,
            steer: 0,
            bend: 0,
            mouthTakeover: Self.smoothstep(Self.ramp(t, 0, 0.15)) * (1 - Self.smoothstep(Self.ramp(t, 2.5, 2.9))),
            cheekPuff: blow.cheekPuff,
            pucker: blow.pucker,
            bubbles: blow.bubbles
        )
    }

    /// Fins straight to full power, easing off over the last third.
    private static func effort(_ u: Float) -> Float {
        smoothstep(ramp(u, 0, 0.12)) * (1 - smoothstep(ramp(u, 0.7, 1)))
    }

    private static func ramp(_ x: Float, _ from: Float, _ to: Float) -> Float {
        min(max((x - from) / (to - from), 0), 1)
    }

    private static func smoothstep(_ x: Float) -> Float { x * x * (3 - 2 * x) }
}
