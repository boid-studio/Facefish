import Foundation
import simd

/// A lap around the bowl along a fixed path: the fish turns, swims away into the depth, crosses
/// behind and comes back in to its home spot, facing where it swims and banking into turns.
///
/// The path is a closed loop through `points` (metres, in the avatar's scene frame: +X screen
/// right, +Y up, +Z toward the camera; the fish's home is the origin). Edit the points to change
/// it; the curve runs smoothly through them (Catmull-Rom).
///
/// Every lap is a little different: it starts from wherever the fish is, goes off to the side the
/// fish already faces (mirroring the path), stretches and lifts the path a bit, surges and eases
/// on the way, and rolls off level now and then.
struct SwimAround {
    /// Where the lap goes. Keep the first and last at the origin (home).
    var points: [SIMD3<Float>] = [
        [0, 0, 0],
        [0.10, 0.02, -0.12],
        [0.14, 0.05, -0.36],
        [0.03, 0.07, -0.62],
        [-0.12, 0.05, -0.45],
        [-0.13, 0.01, -0.18],
        [0, 0, 0],
    ]
    /// Seconds for an average lap; each one is up to 15% quicker or slower.
    var duration: Float = 5.3
    /// Seconds the fins work before the fish sets off; the body starts turning once they have.
    var windUp: Float = 0.35

    private(set) var isActive = false
    private var elapsed: Float = 0
    private var lapDuration: Float = 5.3
    /// 0...1 along the path.
    private var distance: Float = 0
    private var path: [SIMD3<Float>] = []
    /// Where the fish was when the lap started; the path is pulled toward it at the start.
    private var origin = SIMD3<Float>(repeating: 0)
    /// Surges in pace and rolls off level along this lap: (amount, cycles, phase).
    private var surge = SIMD3<Float>(0, 1, 0)
    private var surgeTotal: Float = 1
    private var roll = SIMD3<Float>(0, 1, 0)

    /// What the swim contributes this frame.
    struct Pose {
        /// 0 = not swimming (live head pose), 1 = fully on the path.
        var weight: Float
        var position: SIMD3<Float>
        /// The direction of travel (unit), for facing and banking.
        var heading: SIMD3<Float>
        /// Where the path heads a third of a second from now: the fins steer toward it before the
        /// body turns.
        var ahead: SIMD3<Float>
        /// 0...1, how fast the fish is going right now (drives the tail beat and the body wave).
        var speed: Float
        /// 0...1, how hard the fins and tail work (hardest when setting off).
        var effort: Float
        /// Extra roll (radians) on the way, so the fish doesn't stay level.
        var roll: Float
        /// 0 while the fins wind up (the body holds its pose), 1 once the body follows the path.
        var bodyFollow: Float
    }

    /// Starts a lap from `position` (where the fish is now). `side` +1 sets off toward screen
    /// right (the fish's left), -1 toward screen left.
    mutating func start(from position: SIMD3<Float>, side: Float) {
        origin = position
        let spread = Float.random(in: 0.8...1.05)
        let depth = Float.random(in: 0.85...1.1)
        path = points.enumerated().map { index, point in
            let inner = index > 0 && index < points.count - 1
            return SIMD3(point.x * side * spread, point.y + (inner ? Float.random(in: -0.03...0.03) : 0), point.z * depth)
        }
        lapDuration = duration * Float.random(in: 0.85...1.15)
        surge = [Float.random(in: 0.15...0.3), Float.random(in: 1.5...2.5), Float.random(in: 0...(2 * .pi))]
        surgeTotal = (0..<200).reduce(0) { $0 + pace((Float($1) + 0.5) / 200) } / 200
        roll = [Float.random(in: 0.15...0.4) * (Bool.random() ? 1 : -1), Float.random(in: 1...2), Float.random(in: 0...(2 * .pi))]
        elapsed = 0
        distance = 0
        isActive = true
    }

    mutating func update(deltaTime: Float) -> Pose? {
        guard isActive else { return nil }
        elapsed += deltaTime
        let total = windUp + lapDuration
        guard elapsed < total else {
            isActive = false
            return nil
        }
        // Along the path at the lap's pace (none during the wind-up).
        let step = max(0, min(elapsed - windUp, deltaTime)) / lapDuration
        let t = min(max((elapsed - windUp) / lapDuration, 0), 1)
        distance = min(1, distance + pace(t - step / 2) / surgeTotal * step)
        let rate = pace(t) / surgeTotal
        let position = point(at: distance) + origin * (1 - distance)
        let heading = direction(at: distance)
        let ahead = direction(at: min(1, distance + max(rate * 0.35 / lapDuration, 0.03)))
        let speed = min(1, rate / 1.5)
        // Full power to set off, then with the speed.
        let setOff = 1 - Self.smoothstep(min(max((elapsed - windUp) / 0.6, 0), 1))
        let effort = max(setOff, 0.45 + 0.55 * speed)
        let rollAngle = roll.x * sin(2 * .pi * roll.y * distance + roll.z) * sin(.pi * distance)
        let bodyFollow = Self.smoothstep(min(max((elapsed - 0.7 * windUp) / 0.3, 0), 1))
        // It starts from where the fish is, so it can take over quickly; it hands back slowly.
        let weight = Self.smoothstep(min(elapsed / 0.3, 1)) * Self.smoothstep(min((total - elapsed) / 0.8, 1))
        return Pose(
            weight: weight, position: position, heading: heading, ahead: ahead,
            speed: speed, effort: effort, roll: rollAngle, bodyFollow: bodyFollow
        )
    }

    /// How fast along the path at `t` (0...1 of the lap's time): eased in and out, with surges.
    private func pace(_ t: Float) -> Float {
        6 * t * (1 - t) * (1 + surge.x * sin(2 * .pi * surge.y * t + surge.z))
    }

    private func direction(at s: Float) -> SIMD3<Float> {
        let heading = point(at: min(1, s + 0.01)) - point(at: max(0, s - 0.01))
        let length = simd_length(heading)
        return length > 1e-5 ? heading / length : [0, 0, -1]
    }

    /// The point at `s` (0...1 along the whole loop).
    private func point(at s: Float) -> SIMD3<Float> {
        let segments = path.count - 1
        let x = min(max(s, 0), 1) * Float(segments)
        let i = min(Int(x), segments - 1)
        let t = x - Float(i)
        let p0 = path[max(i - 1, 0)], p1 = path[i], p2 = path[i + 1], p3 = path[min(i + 2, segments)]
        let t2 = t * t, t3 = t2 * t
        return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
    }

    private static func smoothstep(_ x: Float) -> Float { x * x * (3 - 2 * x) }
}
