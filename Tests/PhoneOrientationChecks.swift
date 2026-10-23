import Foundation
import simd

// swiftc ARFace/Tracking/PhoneOrientation.swift Tests/PhoneOrientationChecks.swift -o /tmp/PhoneOrientationChecks
// /tmp/PhoneOrientationChecks
@main
struct PhoneOrientationChecks {
    static func main() throws {
        var resolver = PhoneOrientationResolver()
        resolver.update(mode: .automatic, gravity: nil)
        precondition(!resolver.isUpsideDown, "Automatic must start upright without sensor data.")

        resolver.update(mode: .automatic, gravity: [0, 1, 0])
        precondition(resolver.isUpsideDown, "Positive Y gravity must detect upside-down mounting.")
        for gravity: SIMD3<Float> in [[0, 0, -1], [1, 0, 0], [0, -0.49, 0], [0, 0.49, 0]] {
            resolver.update(mode: .automatic, gravity: gravity)
            precondition(resolver.isUpsideDown, "Ambiguous gravity must retain the last orientation.")
        }
        resolver.update(mode: .automatic, gravity: nil)
        precondition(resolver.isUpsideDown, "Missing sensor data must retain the last orientation.")
        resolver.update(mode: .automatic, gravity: [0, -1, 0])
        precondition(!resolver.isUpsideDown, "Negative Y gravity must restore upright mounting.")
        resolver.update(mode: .automatic, gravity: [0, 0.49, 0])
        precondition(!resolver.isUpsideDown, "Noise must not flip an upright orientation.")

        resolver.update(mode: .upsideDown, gravity: [0, -1, 0])
        precondition(resolver.isUpsideDown, "Manual upside-down must override the sensor.")
        resolver.update(mode: .upright, gravity: [0, 1, 0])
        precondition(!resolver.isUpsideDown, "Manual upright must override the sensor.")
        resolver.update(mode: .upsideDown, gravity: nil)
        precondition(resolver.isUpsideDown, "Manual mode must work without motion sensors.")
        resolver.update(mode: .automatic, gravity: [0, -1, 0])
        precondition(!resolver.isUpsideDown, "Returning to Automatic must resume sensor detection.")

        let mounting = simd_quatf(angle: .pi, axis: SIMD3<Float>(0, 0, 1))
        for mode in PhoneOrientation.allCases {
            for upsideDown in [false, true] {
                resolver.update(mode: mode, gravity: upsideDown ? [0, 1, 0] : [0, -1, 0])
                let correctedMount = mode == .upsideDown || (mode == .automatic && upsideDown)
                for yaw: Float in [-0.6, 0, 0.6] {
                    for pitch: Float in [-0.4, 0, 0.4] {
                        for roll: Float in [-0.3, 0, 0.3] {
                            let intended = simd_quatf(angle: yaw, axis: [0, 1, 0])
                                * simd_quatf(angle: pitch, axis: [1, 0, 0])
                                * simd_quatf(angle: roll, axis: [0, 0, 1])
                            let raw = correctedMount ? mounting * intended : intended
                            let corrected = resolver.corrected(rotation: raw)
                            precondition(abs(simd_dot(corrected.vector, intended.vector)) > 0.99999,
                                         "Correction must preserve yaw, pitch and roll in the face's local axes.")
                            let canvas = correctedMount ? mounting : simd_quatf(angle: 0, axis: [0, 0, 1])
                            // The local canvas turns with the mounting; the external canvas does not.
                            let physicalPhone = simd_inverse(canvas) * canvas * corrected
                            precondition(abs(simd_dot(physicalPhone.vector, intended.vector)) > 0.99999,
                                         "The physical phone and external display must show the same head pose.")
                            let backgroundUp = SIMD3<Float>(0, 1, 0)
                            let physicalBackgroundUp = simd_inverse(canvas).act(canvas.act(backgroundUp))
                            precondition(simd_distance(physicalBackgroundUp, backgroundUp) < 0.00001,
                                         "The background must remain physically upright with the fish.")
                        }
                    }
                }
            }
        }

        resolver.update(mode: .upsideDown, gravity: nil)
        let gravity = resolver.corrected(vector: SIMD3<Float>(0, 1, 0))
        precondition(gravity == SIMD3<Float>(0, -1, 0), "Corrected water gravity must point down.")
        let acceleration = SIMD3<Float>(0.2, -0.3, 0.4)
        let correctedAcceleration = resolver.corrected(vector: acceleration)
        precondition(correctedAcceleration == SIMD3<Float>(-0.2, 0.3, 0.4),
                     "Motion correction must reverse X/Y but preserve depth.")
        precondition(abs(simd_length(correctedAcceleration) - simd_length(acceleration)) < 0.00001,
                     "Motion correction must preserve acceleration magnitude.")
        resolver.update(mode: .upright, gravity: nil)
        precondition(resolver.corrected(vector: acceleration) == acceleration,
                     "Upright motion must remain unchanged.")

        for mode in PhoneOrientation.allCases {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(PhoneOrientation.self, from: data)
            precondition(decoded == mode, "Orientation values must round-trip for Bluetooth.")
            precondition(PhoneOrientation(rawValue: mode.rawValue) == mode,
                         "Orientation values must round-trip for saved settings.")
        }
        print("Phone orientation checks passed.")
    }
}
