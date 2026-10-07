import ARKit
import Foundation
import Observation

/// Cleans up ARKit's raw values before the fish uses them:
///
/// 1. **Center face**: ARKit rarely reads 0 on a relaxed face (jawOpen ~0.1, mouthLowerDown ~0.08,
///    eyeSquint ~0.2...), which keeps the fish's lips parted. `beginCapture()` records the
///    performer's resting face (the median over 1.5 s of tracking, so a blink doesn't count); each
///    value is then rescaled to (raw - rest) / (1 - rest): rest reads 0, a full expression still 1.
///    Saved on the device.
/// 2. **Pucker priority**: a pucker turns funnel down, so a closed kiss stays closed (funnel opens
///    the lips into an "O").
/// 3. **Lip seal**: "jaw down, lips closed" arrives as jawOpen and mouthClose together. The fish's
///    jawOpen is a deep cartoon gape, so a strong mouthClose stretches the lips a long way; instead,
///    most of the matched pair becomes less jaw (the jaw comes up), and the lips still meet.
@Observable
final class FaceCalibration {
    static let shared = FaceCalibration()

    private(set) var rest: [ARFaceAnchor.BlendShapeLocation: Float] = [:]
    private(set) var isCapturing = false
    var enabled = true { didSet { save() } }
    /// 0 = off; 1 = lips closed entirely by raising the jaw.
    var lipSeal: Float = 0.75 { didSet { save() } }
    /// 0 = off; 1 = a full pucker removes all funnel.
    var puckerPriority: Float = 1 { didSet { save() } }

    @ObservationIgnored private var samples: [[ARFaceAnchor.BlendShapeLocation: Float]] = []
    @ObservationIgnored private var captureStart = Date.distantPast
    private static let captureSeconds: TimeInterval = 1.5
    private static let defaultsKey = "faceCalibration"

    private init() {
        load()
    }

    /// Record the resting face from the next 1.5 s of tracking. Hold a relaxed face meanwhile.
    func beginCapture() {
        samples.removeAll()
        captureStart = Date()
        isCapturing = true
    }

    func clear() {
        rest = [:]
        save()
    }

    /// Call with every tracked frame (any number of callers is fine).
    func feed(_ blendShapes: [ARFaceAnchor.BlendShapeLocation: Float]) {
        guard isCapturing else { return }
        samples.append(blendShapes)
        let elapsed = Date().timeIntervalSince(captureStart)
        guard elapsed >= Self.captureSeconds else { return }
        isCapturing = false
        guard samples.count >= 5 else { return }
        var median: [ARFaceAnchor.BlendShapeLocation: Float] = [:]
        for location in BlendShapeMapping.allLocations {
            let values = samples.compactMap { $0[location] }.sorted()
            if !values.isEmpty { median[location] = values[values.count / 2] }
        }
        rest = median
        enabled = true
        save()
    }

    /// The values the fish should use, still on ARKit's own sides (mirroring happens later).
    func adjusted(_ raw: [ARFaceAnchor.BlendShapeLocation: Float]) -> [ARFaceAnchor.BlendShapeLocation: Float] {
        var weights = raw
        if enabled, !rest.isEmpty {
            for (location, value) in raw {
                guard let resting = rest[location], resting < 0.95 else { continue }
                weights[location] = max(0, (value - resting) / (1 - resting))
            }
        }
        let pucker = weights[.mouthPucker] ?? 0
        if let funnel = weights[.mouthFunnel] {
            weights[.mouthFunnel] = funnel * (1 - min(max(puckerPriority, 0), 1) * pucker)
        }
        let jaw = weights[.jawOpen] ?? 0
        let close = weights[.mouthClose] ?? 0
        let seal = min(jaw, close) * min(max(lipSeal, 0), 1)
        weights[.jawOpen] = jaw - seal
        weights[.mouthClose] = close - seal
        return weights
    }

    private func save() {
        let stored: [String: Any] = [
            "rest": Dictionary(uniqueKeysWithValues: rest.map { ($0.key.rawValue, Double($0.value)) }),
            "enabled": enabled,
            "lipSeal": Double(lipSeal),
            "puckerPriority": Double(puckerPriority),
        ]
        UserDefaults.standard.set(stored, forKey: Self.defaultsKey)
    }

    private func load() {
        guard let stored = UserDefaults.standard.dictionary(forKey: Self.defaultsKey) else { return }
        if let values = stored["rest"] as? [String: Double] {
            rest = Dictionary(uniqueKeysWithValues: values.map {
                (ARFaceAnchor.BlendShapeLocation(rawValue: $0.key), Float($0.value))
            })
        }
        enabled = stored["enabled"] as? Bool ?? true
        lipSeal = Float(stored["lipSeal"] as? Double ?? 0.75)
        puckerPriority = Float(stored["puckerPriority"] as? Double ?? 1)
    }
}
