import Foundation
import simd

/// Hiding the fish, for the acting, swimming like a fish: from rest she sets off forward, paddling
/// hard to build momentum, curves round in a wide arc to one side and swims off out of frame, faster
/// and faster, and stays out of sight until shown. Shown, she swims back in on an arc from the
/// side and glides into her spot facing the camera.
///
/// Each way is a smooth path (Catmull-Rom) in the avatar's scene frame, in metres: +X screen right,
/// +Y up, +Z toward the camera; the fish's spot is the origin. Like a fish, she doesn't follow it
/// straight: she weaves along it in soft S-curves and floats up and down, rising a little through
/// the turn. The controller faces her along the way she actually goes, as on a lap (SwimAround),
/// the fins steering ahead of a body that turns slowly and softly.
struct HideShow {
    enum Phase { case visible, leaving, hidden, arriving }

    private(set) var phase: Phase = .visible
    /// Seconds to swim out of frame, and back in.
    var leaveDuration: Float = 4.0
    var arriveDuration: Float = 3.4   // (3.4 from out of sight; turning back sets its own)
    /// The S-curves: how far she weaves to either side (metres) and how many times along the way.
    var weave: Float = 0.025
    var weaveCycles: Float = 1.5
    /// How far she floats up and down (metres), and rises through the middle of the swim.
    var float: Float = 0.025
    var rise: Float = 0.035

    private var elapsed: Float = 0
    /// The way she was last going, to turn back from it.
    private(set) var heading = SIMD3<Float>(0, 0, 1)
    /// The path, with a lead-in and a lead-out point that only set its direction at the ends.
    private var path: [SIMD3<Float>] = []

    /// Whether the fish is going or gone (for the Hide/Show button).
    var isHidden: Bool { phase == .leaving || phase == .hidden }

    struct Frame {
        /// Where the fish is on the path (nil once she's out of sight).
        var pose: SwimAround.Pose?
        /// Out of sight: not drawn.
        var hidden: Bool
    }

    /// Swims away from `position` (where the fish is now) to the `side` (+1 screen right, -1 left).
    /// The turn stays in frame (in portrait the view is narrow close up): forward, round, away into
    /// the distance, and only then off to the side.
    mutating func hide(from position: SIMD3<Float>, side s: Float) {
        let away = position + SIMD3(-0.02 * s, 0.07, -0.45)
        let exit = position + SIMD3(0.75 * s, Float.random(in: 0.0...0.2), -0.9)
        path = [
            position + SIMD3(0, 0, -0.08),            // lead-in: she sets off forward, the way she faces
            position,
            position + SIMD3(0.03 * s, 0.01, 0.06),   // forward, gathering speed
            position + SIMD3(0.08 * s, 0.03, 0.02),   // curving to the side
            position + SIMD3(0.07 * s, 0.05, -0.18),  // round, heading away
            away,                                     // back across, smaller in the distance
            exit,                                     // off to the side, out of frame
            exit + (exit - away),                     // lead-out
        ]
        elapsed = 0
        phase = .leaving
    }

    /// Swims back in from the `side` (+1 screen right, -1 left) to `home`, arriving facing the camera.
    mutating func show(to home: SIMD3<Float>, side s: Float) {
        arriveDuration = 3.4
        let entry = home + SIMD3(0.75 * s, Float.random(in: 0.0...0.2), -0.9)
        let far = home + SIMD3(-0.02 * s, 0.06, -0.45)
        path = [
            entry + (entry - far),                    // lead-in
            entry,                                    // out of frame, in the distance
            far,                                      // into view, small and far
            home + SIMD3(0.07 * s, 0.03, -0.18),      // S-curving closer
            home + SIMD3(0.03 * s, 0.01, -0.05),
            home,
            home + SIMD3(0, 0, 0.1),                  // lead-out: she ends facing the camera
        ]
        elapsed = 0
        phase = .arriving
    }

    /// Shown while still swimming away: she carries on a little with her momentum, curves round in
    /// a U-turn and swims back to `home`, from exactly where she is.
    mutating func turnBack(from position: SIMD3<Float>, to home: SIMD3<Float>) {
        let going = heading
        let ahead = position + going * 0.1
        let s: Float = home.x - ahead.x >= 0 ? 1 : -1
        let round = (ahead + home) / 2 + SIMD3(0.08 * s, 0.03, -0.06)
        path = [
            position - going * 0.1,                   // lead-in: the way she was going
            position,
            ahead,                                    // momentum carries her on a little
            round,                                    // curving back
            home + SIMD3(0.03 * s, 0.01, -0.05),
            home,
            home + SIMD3(0, 0, 0.1),                  // lead-out: she ends facing the camera
        ]
        // Further away takes longer.
        arriveDuration = min(max(1.8 + simd_length(home - position) * 2.5, 2.2), 3.4)
        elapsed = 0
        phase = .arriving
    }

    /// The first direction of travel, to face her along it as she comes in.
    var startHeading: SIMD3<Float> { path.count > 2 ? direction(at: 0) : [0, 0, 1] }

    mutating func update(deltaTime: Float) -> Frame? {
        switch phase {
        case .visible:
            return nil
        case .hidden:
            return Frame(pose: nil, hidden: true)
        case .leaving:
            elapsed += deltaTime
            let u = min(elapsed / leaveDuration, 1)
            if u >= 1 { phase = .hidden }
            // From rest, faster and faster: distance u^2 (1.5 - 0.5u), speed rising to the end.
            let distance = u * u * (1.5 - 0.5 * u)
            let speed = (3 * u - 1.5 * u * u) / 1.5
            return Frame(pose: pose(at: distance, speed: speed,
                                    weight: 1,   // starts exactly where she is, facing as she does
                                    effort: 0.75 + 0.25 * min(u / 0.2, 1)), hidden: false)
        case .arriving:
            elapsed += deltaTime
            let u = min(elapsed / arriveDuration, 1)
            if u >= 1 { phase = .visible }
            // In fast, gliding to a stop: the mirror of leaving.
            let v = 1 - u
            let distance = 1 - v * v * (1.5 - 0.5 * v)
            let speed = (3 * v - 1.5 * v * v) / 1.5
            return Frame(pose: pose(at: distance, speed: speed,
                                    weight: 1 - Self.smoothstep(min(max((u - 0.85) / 0.15, 0), 1)),
                                    effort: 0.3 + 0.7 * speed), hidden: false)
        }
    }

    private mutating func pose(at distance: Float, speed: Float, weight: Float, effort: Float) -> SwimAround.Pose {
        heading = direction(at: distance)
        return SwimAround.Pose(
            weight: weight,
            position: place(at: distance),
            heading: direction(at: distance),
            ahead: direction(at: min(1, distance + 0.12)),
            speed: min(1, speed),
            effort: effort,
            roll: 0,
            bodyFollow: 1
        )
    }

    private func direction(at s: Float) -> SIMD3<Float> {
        let heading = place(at: min(1, s + 0.01)) - place(at: max(0, s - 0.01))
        let length = simd_length(heading)
        return length > 1e-5 ? heading / length : [0, 0, 1]
    }

    /// Where she is at `s`: on the path, weaving to either side of it and floating up and down,
    /// both calm at the ends and strongest mid-swim.
    private func place(at s: Float) -> SIMD3<Float> {
        let s = min(max(s, 0), 1)
        let base = point(at: s)
        let along = point(at: min(1, s + 0.01)) - point(at: max(0, s - 0.01))
        var side = simd_cross(SIMD3<Float>(0, 1, 0), along)
        let length = simd_length(side)
        side = length > 1e-5 ? side / length : [1, 0, 0]
        let envelope = sin(.pi * s)
        let sway = weave * sin(2 * .pi * weaveCycles * s) * envelope
        let lift = (float * sin(2 * .pi * 1.5 * s + 0.7) + rise) * envelope
        return base + side * sway + SIMD3(0, lift, 0)
    }

    /// The point at `s` (0...1 from the first real point to the last; the lead-in and lead-out
    /// only shape the ends).
    private func point(at s: Float) -> SIMD3<Float> {
        let segments = path.count - 3
        let x = min(max(s, 0), 1) * Float(segments)
        let i = min(Int(x), segments - 1)
        let t = x - Float(i)
        let p0 = path[i], p1 = path[i + 1], p2 = path[i + 2], p3 = path[i + 3]
        let t2 = t * t, t3 = t2 * t
        return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
    }

    private static func smoothstep(_ x: Float) -> Float { x * x * (3 - 2 * x) }
}
