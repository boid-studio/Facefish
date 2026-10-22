import CoreMotion
import simd

/// The phone's own movement (it rides in the diving helmet), read each frame for the water.
/// No permission prompt is needed for device motion. Updates start on first use.
final class MotionTracker {
    static let shared = MotionTracker()

    nonisolated struct Reading {
        /// Which way is down, in g (length ~1), in the phone's axes: x right, y up, z out of the
        /// screen as you look at it. Upright in portrait it is (0, -1, 0).
        var gravity: SIMD3<Float>
        /// Acceleration without gravity, in g, same axes.
        var acceleration: SIMD3<Float>
    }

    private let manager = CMMotionManager()

    private init() {
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60
        manager.startDeviceMotionUpdates()
    }

    /// The latest reading; nil until the sensors report (or on a device without them).
    var latest: Reading? {
        guard let motion = manager.deviceMotion else { return nil }
        let g = motion.gravity, a = motion.userAcceleration
        return Reading(
            gravity: SIMD3(Float(g.x), Float(g.y), Float(g.z)),
            acceleration: SIMD3(Float(a.x), Float(a.y), Float(a.z))
        )
    }
}
