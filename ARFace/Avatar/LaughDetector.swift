import ARKit
import Foundation

/// Spots laughter, and how hard, from the face and the voice: a smile with crinkled eyes, plus the
/// "ha-ha-ha" rhythm (the jaw and the voice pulsing a few times a second).
///
/// `intensity` (0...1) rises quickly, holds a moment and fades, so the fish's laugh doesn't flicker.
/// `pulse` (-1...1) follows each "ha" (the jaw above or below its recent average), for bounces.
struct LaughDetector {
    private(set) var intensity: Float = 0
    private(set) var pulse: Float = 0
    /// What the score is made of, for tuning in the debug panel.
    private(set) var smile: Float = 0
    private(set) var squint: Float = 0
    private(set) var jawRhythm: Float = 0
    private(set) var voiceRhythm: Float = 0

    private var jawFast: Float = 0, jawSlow: Float = 0, jawEnergy: Float = 0
    private var voiceFast: Float = 0, voiceSlow: Float = 0, voiceEnergy: Float = 0
    private var hold: Float = 0

    /// `weights`: this frame's (calibrated) blend shapes, nil without a face. `voice`: the mic level.
    mutating func update(weights: [ARFaceAnchor.BlendShapeLocation: Float]?, voice: Float, deltaTime: Float) {
        guard let weights else {
            intensity = max(0, intensity - deltaTime / 0.4)
            pulse = 0
            return
        }
        func w(_ location: ARFaceAnchor.BlendShapeLocation) -> Float { weights[location] ?? 0 }
        func follow(_ value: inout Float, _ target: Float, _ timeConstant: Float) {
            value += (target - value) * (1 - exp(-deltaTime / timeConstant))
        }

        // The rhythm: the jaw (and the voice) minus their slow average leaves the "ha" pulses.
        follow(&jawFast, w(.jawOpen), 0.03)
        follow(&jawSlow, w(.jawOpen), 0.35)
        let jawBand = jawFast - jawSlow
        follow(&jawEnergy, jawBand * jawBand, 0.5)
        follow(&voiceFast, voice, 0.03)
        follow(&voiceSlow, voice, 0.35)
        let voiceBand = voiceFast - voiceSlow
        follow(&voiceEnergy, voiceBand * voiceBand, 0.5)
        jawRhythm = sqrt(jawEnergy)
        voiceRhythm = sqrt(voiceEnergy)
        pulse = min(max(jawBand / 0.12, -1), 1)

        smile = (w(.mouthSmileLeft) + w(.mouthSmileRight)) / 2
        squint = max((w(.cheekSquintLeft) + w(.cheekSquintRight)) / 2, (w(.eyeSquintLeft) + w(.eyeSquintRight)) / 2)
        let score = Self.smoothstep(0.25, 0.55, smile) * min(1,
            0.35 * Self.smoothstep(0.2, 0.5, squint)
            + Self.smoothstep(0.04, 0.12, jawRhythm)
            + 0.6 * Self.smoothstep(0.03, 0.1, voiceRhythm))

        // Starts on a clear laugh, keeps going on a weaker one, lets go after a short hold.
        let laughing = score > (intensity > 0.05 ? 0.25 : 0.45)
        if laughing {
            hold = 0.3
            follow(&intensity, max(intensity, score), 0.12)
        } else {
            hold -= deltaTime
            if hold <= 0 { follow(&intensity, 0, 0.6) }
        }
    }

    private static func smoothstep(_ from: Float, _ to: Float, _ x: Float) -> Float {
        let t = min(max((x - from) / (to - from), 0), 1)
        return t * t * (3 - 2 * t)
    }
}

/// The laugh detector's numbers, for the debug panel.
struct LaughReadout: Equatable {
    var intensity: Float = 0
    var smile: Float = 0
    var squint: Float = 0
    var jawRhythm: Float = 0
    var voiceRhythm: Float = 0
}
