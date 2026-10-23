import Foundation
import simd

/// The water surface near the top of the screen, sloshing with the phone (the helmet).
///
/// The water stays level with the world, so when the phone tilts the line tilts the other way on
/// screen, and when the phone is pushed the water lags behind and sways back (a damped spring).
/// A jump moves the whole surface: it drops as the phone rises, surges up in the air and on
/// landing, and bobs before it settles. Two standing waves and a slow swell ride on top. The small ripples are simulated on the GPU
/// (GlassBubbleEffect); this hands it the drops that start them.
///
/// Everything is in screen terms: x across the screen 0...1, heights as a fraction of the screen's
/// height, positive up. Cheap: a few dozen numbers per frame.
nonisolated struct WaterSurface {
    /// Where the still water sits, from the top of the screen (0.2 = 80% up).
    var level: Float = 0.2
    /// How strongly the water reacts to the phone moving (0 = still, 1 = as designed).
    var gain: Float = 1
    /// The most the line tilts on screen, however far the phone leans (radians).
    var maxTilt: Float = 30 * .pi / 180

    /// What the renderer needs this frame.
    struct Frame {
        /// Where the line sits now, from the top of the screen, heave included.
        var level: Float
        /// The line's slope on screen (height per width, y up), from the tilt.
        var tilt: Float
        /// Extra height across the screen, `heights.count` samples from left to right.
        var heights: [Float]
        /// New ripple drops: (x 0...1, depth 0...1 from the front edge back, radius in cells, strength).
        var drops: [SIMD4<Float>]
        var time: Float

        /// The line's height (from the top, 0...1) at screen x (0...1), as drawn without the
        /// small ripples. `aspect` is the screen's width / height.
        func lineY(atScreenX x: Float, aspect: Float) -> Float {
            let fx = min(max(x, 0), 1) * Float(heights.count - 1)
            let i = min(Int(fx), heights.count - 2)
            let lift = heights[i] + (heights[i + 1] - heights[i]) * (fx - Float(i))
            return level - tilt * (x - 0.5) * aspect - lift
        }
    }

    static let sampleCount = 64

    private var angle: Float = 0, angleVelocity: Float = 0, lastAngleVelocity: Float = 0
    private var sway: Float = 0, swayVelocity: Float = 0      // the half-wave across the screen
    private var chop: Float = 0, chopVelocity: Float = 0      // the next one up
    private var heave: Float = 0, heaveVelocity: Float = 0    // the whole surface up and down (screen fraction, down)
    private var time: Float = 0
    private var dropBacklog: Float = 0

    mutating func update(deltaTime: Float, motion: MotionTracker.Reading?) -> Frame {
        time += deltaTime
        // Apparent gravity: gravity, minus the phone's own push (the water is left behind).
        var target: Float = 0
        var lift: Float = 0   // acceleration along real "up", in g (jumps, bobbing)
        if let motion {
            let down = SIMD2(motion.gravity.x - motion.acceleration.x * gain,
                             motion.gravity.y - motion.acceleration.y * gain)
            // Lying flat, gravity hardly points across the screen and its direction there is
            // noise: the tilt fades out as the phone lies down (upright in a helmet it is full).
            let upright = simd_length(SIMD2(motion.gravity.x, motion.gravity.y))
            let trust = min(max((upright - 0.35) / 0.35, 0), 1)
            target = min(max(atan2(down.x, -down.y), -maxTilt), maxTilt) * trust * trust * (3 - 2 * trust)
            let gravityLength = simd_length(motion.gravity)
            if gravityLength > 0.1 {
                lift = -simd_dot(motion.acceleration, motion.gravity / gravityLength) * gain
            }
        }

        // The tilt follows on a soft spring (about one sway a second), so it overshoots and rocks.
        let steps = max(1, Int((deltaTime * 240).rounded(.up)))
        let step = deltaTime / Float(steps)
        let omega: Float = 2 * .pi * 0.9
        for _ in 0..<steps {
            angleVelocity += (omega * omega * (target - angle) - 2 * 0.14 * omega * angleVelocity) * step
            angle += angleVelocity * step
        }
        let angleAcceleration = (angleVelocity - lastAngleVelocity) / max(deltaTime, 1e-3)
        lastAngleVelocity = angleVelocity

        // Standing waves, rung by the tilt swinging and by bobbing up and down.
        let omega2: Float = 2 * .pi * 1.4, omega3: Float = 2 * .pi * 1.9
        for _ in 0..<steps {
            swayVelocity += (-omega2 * omega2 * sway - 2 * 0.08 * omega2 * swayVelocity
                             + 0.06 * angleAcceleration + 1.5 * lift) * step
            sway += swayVelocity * step
            chopVelocity += (-omega3 * omega3 * chop - 2 * 0.08 * omega3 * chopVelocity
                             + 0.04 * angleAcceleration) * step
            chop += chopVelocity * step
        }
        // The whole surface: pushed down as the phone rises (the water is left behind), up as it
        // drops or flies; a soft spring, a few bobs before it settles. A 1 g jump moves it ~4%.
        let omegaHeave: Float = 2 * .pi * 1.2
        for _ in 0..<steps {
            heaveVelocity += (-omegaHeave * omegaHeave * heave - 2 * 0.2 * omegaHeave * heaveVelocity
                              + 2.3 * lift) * step
            heave += heaveVelocity * step
        }
        heave = min(max(heave, -0.08), 0.08)
        sway = min(max(sway, -0.03), 0.03)
        chop = min(max(chop, -0.02), 0.02)

        var heights = [Float](repeating: 0, count: Self.sampleCount)
        for index in heights.indices {
            let x = Float(index) / Float(Self.sampleCount - 1) * 2 - 1   // -1...1 across the screen
            heights[index] = sway * cos(.pi * x) + chop * sin(1.5 * .pi * x)
                + 0.0025 * sin(2 * .pi * 1.3 * x + time * 1.6)          // a slow swell, never dead still
                + 0.0015 * sin(2 * .pi * 2.7 * x - time * 2.3)
        }

        // Drops for the ripples: a few now and then, more while it sloshes.
        let energy = min(1, abs(angleVelocity) * 0.6 + abs(swayVelocity) * 8 + abs(heaveVelocity) * 4)
        dropBacklog += (1.2 + 10 * energy) * deltaTime
        var drops: [SIMD4<Float>] = []
        while dropBacklog >= 1, drops.count < 8 {
            dropBacklog -= 1
            drops.append([Float.random(in: 0.05...0.95), Float.random(in: 0...0.6),
                          Float.random(in: 1.5...3), Float.random(in: 0.25...0.6) * (0.5 + energy)])
        }
        dropBacklog = min(dropBacklog, 1)

        return Frame(level: level + heave, tilt: tan(angle), heights: heights, drops: drops, time: time)
    }
}

/// Keeps the water between frames for the view's update loop (a class, so per-frame changes don't
/// redraw SwiftUI). Motion updates start the first time the water is on.
final class WaterSurfaceDriver {
    private var surface = WaterSurface()

    func frame(deltaTime: Float, enabled: Bool, gain: Float, level: Float) -> WaterSurface.Frame? {
        guard enabled else { return nil }
        surface.gain = gain
        surface.level = level
        let motion = MotionTracker.shared.latest.map { AvatarSession.shared.tracker.correctedMotion($0) }
        return surface.update(deltaTime: deltaTime, motion: motion)
    }
}
