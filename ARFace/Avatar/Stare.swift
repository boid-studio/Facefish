import Foundation
import simd

/// "Stare": she swims right up to the lens, turns her right side to it and stares into it with her
/// right eye, so close it fills the screen, holds it a moment (a slight curious bob and tilt), then
/// swims back to her spot.
///
/// In the avatar's scene frame, metres: +X screen right, +Y up, +Z toward the camera. Turning her
/// by `yaw` about +Y swings her nose toward screen right and her right side toward the lens.
struct Stare {
    struct Pose {
        /// 0...1: how much of the fish the stare has (eases in and out at the ends).
        var weight: Float
        /// Where her centre is.
        var position: SIMD3<Float>
        /// Her turn about the up axis (radians, + nose toward screen right), and a curious tilt.
        var yaw: Float
        var roll: Float
        /// 0...1: how hard the fins work.
        var effort: Float
        /// 0...1: how far her eyes turn to the lens (EyeRig.lookOverride).
        var gaze: Float
    }

    /// How far she turns her right side to the lens (radians): with her eyes turned full right, the
    /// right eye looks straight into it.
    static let yaw: Float = 0.5

    private(set) var isActive = false
    private var elapsed: Float = 0
    private var home = SIMD3<Float>(repeating: 0)
    private var spot = SIMD3<Float>(repeating: 0)
    private var approach: Float = 1.6
    private let hold: Float = 2.8
    private var retreat: Float = 1.5
    private var total: Float { approach + hold + retreat }

    /// From `home` (her spot now) to `spot`, where her centre goes for the eye to be at the lens.
    mutating func start(from home: SIMD3<Float>, to spot: SIMD3<Float>) {
        self.home = home
        self.spot = spot
        let distance = simd_length(spot - home)
        approach = min(max(1.0 + distance * 1.2, 1.3), 3.0)
        retreat = min(max(0.9 + distance * 1.1, 1.2), 2.6)
        elapsed = 0
        isActive = true
    }

    mutating func stop() { isActive = false }

    mutating func update(deltaTime: Float) -> Pose? {
        guard isActive else { return nil }
        elapsed += deltaTime
        if elapsed >= total {
            isActive = false
            return nil
        }
        let t = elapsed
        let weight = Self.smoothstep(min(t / 0.3, 1)) * Self.smoothstep(min((total - t) / 0.45, 1))
        if t < approach {
            // Swims in, a little arc up and to the side, facing the lens, turning her side to it
            // as she arrives.
            let u = Self.smootherstep(t / approach)
            let arc = sin(.pi * u) * SIMD3<Float>(-0.025, 0.02, 0)
            let turn = Self.smoothstep(min(max((t / approach - 0.45) / 0.55, 0), 1))
            return Pose(weight: weight, position: home + (spot - home) * u + arc,
                        yaw: Self.yaw * turn, roll: 0.12 * turn,
                        effort: 0.75 * (1 - 0.6 * u), gaze: turn)
        } else if t < approach + hold {
            // Up close: a slow bob and a little curious tilt, sculling to stay put.
            let h = t - approach
            let bob = SIMD3<Float>(0.002 * sin(h * 2.2), 0.003 * sin(h * 1.6), 0.004 * sin(h * 1.1))
            return Pose(weight: weight, position: spot + bob,
                        yaw: Self.yaw + 0.04 * sin(h * 0.9), roll: 0.12 + 0.05 * sin(h * 1.3),
                        effort: 0.18, gaze: 1)
        } else {
            // Backs off home, turning to face out again.
            let u = Self.smootherstep((t - approach - hold) / retreat)
            let turn = 1 - Self.smoothstep(min(u / 0.6, 1))
            let arc = sin(.pi * u) * SIMD3<Float>(0.02, 0.015, 0)
            return Pose(weight: weight, position: spot + (home - spot) * u + arc,
                        yaw: Self.yaw * turn, roll: 0.12 * turn,
                        effort: 0.5 * sin(.pi * u) + 0.2, gaze: turn)
        }
    }

    private static func smoothstep(_ x: Float) -> Float { x * x * (3 - 2 * x) }
    private static func smootherstep(_ x: Float) -> Float { x * x * x * (x * (x * 6 - 15) + 10) }
}
