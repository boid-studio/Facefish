import ARKit
import OSLog
import RealityKit
import simd

/// Turns the eyeballs (`Eye_L` / `Eye_R`) from ARKit's eyeLook blend shapes.
///
/// Each eye turns about its own centre (the entity's origin), in its own local axes, which keep
/// Blender's: +X is the fish's left, +Z up, -Y forward. Left-right turns are about local Z
/// (+ looks toward the fish's left), up-down about local X (+ looks down).
final class EyeRig {
    /// Radians an eye turns at a full look (eyeLook* = 1).
    var range: Float = 0.45

    private struct Eye {
        let entity: Entity
        let rest: simd_quatf
        var yaw: Float = 0
        var pitch: Float = 0
    }

    private let logger = Logger(subsystem: "ARFace", category: "EyeRig")
    private var left: Eye?
    private var right: Eye?
    private var isEnabled = true

    init(model: Entity) {
        left = Self.find(in: model, named: "eyel").map { Eye(entity: $0, rest: $0.orientation) }
        right = Self.find(in: model, named: "eyer").map { Eye(entity: $0, rest: $0.orientation) }
        if left == nil || right == nil {
            logger.error("Fish model is missing eye entities (Eye_L / Eye_R); gaze is off for the missing ones.")
        }
    }

    /// The fish's left and right eye are found by name, ignoring case, "." and "_" (Eye.L, Eye_L, eyel).
    static func find(in entity: Entity, named key: String) -> Entity? {
        if entity.name.lowercased().filter({ $0.isLetter || $0.isNumber }) == key { return entity }
        for child in entity.children {
            if let found = find(in: child, named: key) { return found }
        }
        return nil
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if !enabled {
            left.map { $0.entity.orientation = $0.rest }
            right.map { $0.entity.orientation = $0.rest }
            left?.yaw = 0; left?.pitch = 0
            right?.yaw = 0; right?.pitch = 0
        }
    }

    /// `weight` reads a blend shape for the fish's side: the caller has already swapped left and right
    /// for mirror mode, so `.eyeLookOutLeft` is "the fish's left eye looking toward the fish's left".
    /// Pass nil while there is no tracked face: the eyes ease back to looking straight ahead.
    func update(weight: ((ARFaceAnchor.BlendShapeLocation) -> Float)?, deltaTime: TimeInterval) {
        guard isEnabled, deltaTime.isFinite, deltaTime > 0 else { return }
        var yawL: Float = 0, pitchL: Float = 0, yawR: Float = 0, pitchR: Float = 0
        if let weight {
            // Looking toward the fish's left is "out" for its left eye and "in" for its right eye.
            yawL = (weight(.eyeLookOutLeft) - weight(.eyeLookInLeft)) * range
            yawR = (weight(.eyeLookInRight) - weight(.eyeLookOutRight)) * range
            pitchL = (weight(.eyeLookDownLeft) - weight(.eyeLookUpLeft)) * range
            pitchR = (weight(.eyeLookDownRight) - weight(.eyeLookUpRight)) * range
        }
        // Quick, like a real eye, but enough to hide tracking jitter.
        let alpha = Float(1 - exp(-deltaTime / (weight == nil ? 0.15 : 0.02)))
        step(&left, yaw: yawL, pitch: pitchL, alpha: alpha)
        step(&right, yaw: yawR, pitch: pitchR, alpha: alpha)
    }

    private func step(_ eye: inout Eye?, yaw: Float, pitch: Float, alpha: Float) {
        guard var current = eye else { return }
        current.yaw += alpha * (min(max(yaw, -range), range) - current.yaw)
        current.pitch += alpha * (min(max(pitch, -range), range) - current.pitch)
        current.entity.orientation = current.rest
            * simd_quatf(angle: current.yaw, axis: [0, 0, 1])
            * simd_quatf(angle: current.pitch, axis: [1, 0, 0])
        eye = current
    }
}

/// Turns the upper eyelids (`Eyelid_L` / `Eyelid_R`) from ARKit's blink, squint and wide shapes.
///
/// Each lid turns about the eyeball's centre (the entity's origin) around its own local X axis,
/// so it slides over the eye instead of cutting into it; + closes. The modelled lid is the
/// neutral pose (the artist rotated it about 23 degrees down in Blender), and `angle` more closes
/// it fully.
final class LidRig {
    /// Degrees from the modelled lid to fully closed.
    var angle: Float = 77
    /// Extra closing with no blink, as a fraction of a full blink (0 = as modelled).
    var neutral: Float = 0

    private struct Lid {
        let entity: Entity
        let rest: simd_quatf
        var closed: Float = 0
    }

    private let logger = Logger(subsystem: "ARFace", category: "LidRig")
    private var left: Lid?
    private var right: Lid?
    private var isEnabled = true

    init(model: Entity) {
        left = EyeRig.find(in: model, named: "eyelidl").map { Lid(entity: $0, rest: $0.orientation) }
        right = EyeRig.find(in: model, named: "eyelidr").map { Lid(entity: $0, rest: $0.orientation) }
        if left == nil || right == nil {
            logger.error("Fish model is missing eyelid entities (Eyelid_L / Eyelid_R); blinks are off for the missing ones.")
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if !enabled {
            for lid in [left, right].compactMap({ $0 }) { lid.entity.orientation = lid.rest }
            left?.closed = 0
            right?.closed = 0
        }
    }

    /// `weight` reads a blend shape for the fish's side (left and right already swapped for mirror
    /// mode). Pass nil while there is no tracked face: the lids ease back to their neutral pose.
    func update(weight: ((ARFaceAnchor.BlendShapeLocation) -> Float)?, deltaTime: TimeInterval) {
        guard isEnabled, deltaTime.isFinite, deltaTime > 0 else { return }
        var targetL = Self.closed(0, neutral: neutral)
        var targetR = targetL
        if let weight {
            targetL = Self.closed(Self.amount(blink: weight(.eyeBlinkLeft), squint: weight(.eyeSquintLeft), wide: weight(.eyeWideLeft)), neutral: neutral)
            targetR = Self.closed(Self.amount(blink: weight(.eyeBlinkRight), squint: weight(.eyeSquintRight), wide: weight(.eyeWideRight)), neutral: neutral)
        }
        // Blinks are fast; keep up with them. Without tracking, settle slowly.
        let alpha = Float(1 - exp(-deltaTime / (weight == nil ? 0.15 : 0.012)))
        step(&left, to: targetL, alpha: alpha)
        step(&right, to: targetR, alpha: alpha)
    }

    /// Blink, plus a little for a squint, minus a little for wide eyes: -0.3 (wide open) ... 1 (shut).
    static func amount(blink: Float, squint: Float, wide: Float) -> Float {
        min(max(blink + 0.35 * squint - 0.25 * wide, -0.3), 1)
    }

    /// How far closed the lid is (1 = full blink, 0 = as modelled): `amount` 0 sits at `neutral`,
    /// 1 closes fully, -0.3 (wide eyes) opens to 0.3 past the modelled lid.
    static func closed(_ amount: Float, neutral: Float) -> Float {
        amount >= 0 ? neutral + (1 - neutral) * amount : neutral + amount * (neutral + 0.3) / 0.3
    }

    private func step(_ lid: inout Lid?, to target: Float, alpha: Float) {
        guard var current = lid else { return }
        current.closed += alpha * (target - current.closed)
        current.entity.orientation = current.rest
            * simd_quatf(angle: angle * .pi / 180 * current.closed, axis: [1, 0, 0])
        lid = current
    }
}
