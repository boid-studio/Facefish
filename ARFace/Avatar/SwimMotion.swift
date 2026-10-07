import Foundation
import simd

/// Gentle life for the whole fish, layered under the tracked head pose: a slow bob and drift,
/// the nose tipping with the bob, and a small body rock in time with the tail's swimming.
///
/// Several sines with unrelated frequencies are summed, so the motion never visibly loops.
/// Works in the avatar root's frame: +Y up, +Z toward the camera (the way the fish faces), +X the
/// fish's left.
struct SwimMotion {
    /// Overall strength (0 = still, 1 = as designed).
    var amount: Float = 1

    private var time: Float = 0
    private var energy: Float = 0.6

    /// Advances the motion. `mouthOpen` (0...1) makes the swimming livelier, like the fins.
    /// `size` is the fish's size in metres; offsets scale with it.
    mutating func update(deltaTime: Float, mouthOpen: Float, size: Float) -> (offset: SIMD3<Float>, rotation: simd_quatf) {
        time += deltaTime
        let targetEnergy = 0.6 + 1.2 * min(1, max(0, mouthOpen))
        energy += (targetEnergy - energy) * (1 - exp(-deltaTime * 3))

        let t = time
        let tau = 2 * Float.pi
        func wave(_ hz: Float, _ phase: Float) -> Float { sin(tau * hz * t + phase) }

        // Slow float: mostly up and down, a little sideways and toward/away from the camera.
        let bob = 0.022 * wave(0.31, 0) + 0.008 * wave(0.73, 1.3)
        let drift = 0.014 * wave(0.17, 0.4) + 0.005 * wave(0.53, 2.1)
        let depth = 0.008 * wave(0.23, 0.9)
        let offset = SIMD3<Float>(drift, bob, depth) * size * amount

        // The nose tips up while rising and down while sinking (follows the bob's speed), with a
        // slow roll; the body rocks a little against the tail's sway (FinRig sways at 4.2 rad/s).
        let degrees = Float.pi / 180
        let pitch = -3 * degrees * (cos(tau * 0.31 * t) + 0.35 * cos(tau * 0.73 * t + 1.3))
        let roll = 2.5 * degrees * wave(0.27, 0.7)
        let rock = 1.5 * degrees * energy * sin(4.2 * t + .pi)
        let rotation = simd_quatf(angle: rock * amount, axis: [0, 1, 0])
            * simd_quatf(angle: pitch * amount, axis: [1, 0, 0])
            * simd_quatf(angle: roll * amount, axis: [0, 0, 1])
        return (offset, rotation)
    }
}
