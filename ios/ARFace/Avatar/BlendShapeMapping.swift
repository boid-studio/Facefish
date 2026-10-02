import ARKit

/// Resolves the model's blend shape (morph target) names to ARKit blend shape locations.
enum BlendShapeMapping {
    /// Explicit model shape name → ARKit location, for names auto-matching can't resolve.
    static let overrides: [String: ARFaceAnchor.BlendShapeLocation] = [:]

    static let allLocations: [ARFaceAnchor.BlendShapeLocation] = [
        .eyeBlinkLeft, .eyeLookDownLeft, .eyeLookInLeft, .eyeLookOutLeft, .eyeLookUpLeft, .eyeSquintLeft, .eyeWideLeft,
        .eyeBlinkRight, .eyeLookDownRight, .eyeLookInRight, .eyeLookOutRight, .eyeLookUpRight, .eyeSquintRight, .eyeWideRight,
        .jawForward, .jawLeft, .jawRight, .jawOpen,
        .mouthClose, .mouthFunnel, .mouthPucker, .mouthLeft, .mouthRight,
        .mouthSmileLeft, .mouthSmileRight, .mouthFrownLeft, .mouthFrownRight,
        .mouthDimpleLeft, .mouthDimpleRight, .mouthStretchLeft, .mouthStretchRight,
        .mouthRollLower, .mouthRollUpper, .mouthShrugLower, .mouthShrugUpper,
        .mouthPressLeft, .mouthPressRight, .mouthLowerDownLeft, .mouthLowerDownRight,
        .mouthUpperUpLeft, .mouthUpperUpRight,
        .browDownLeft, .browDownRight, .browInnerUp, .browOuterUpLeft, .browOuterUpRight,
        .cheekPuff, .cheekSquintLeft, .cheekSquintRight,
        .noseSneerLeft, .noseSneerRight,
        .tongueOut,
    ]

    /// Conventional name, e.g. `eyeBlink_L` → `eyeBlinkLeft`.
    static func displayName(_ location: ARFaceAnchor.BlendShapeLocation) -> String {
        let raw = location.rawValue
        if raw.hasSuffix("_L") { return String(raw.dropLast(2)) + "Left" }
        if raw.hasSuffix("_R") { return String(raw.dropLast(2)) + "Right" }
        return raw
    }

    /// Matches exact names as well as prefixed ones like `Face.jawOpen` or `blendShape1_eyeBlink_L`.
    static func location(forModelShape name: String) -> ARFaceAnchor.BlendShapeLocation? {
        if let override = overrides[name] { return override }
        let key = normalize(name)
        return candidates
            .filter { key.hasSuffix($0.key) }
            .max { $0.key.count < $1.key.count }?
            .location
    }

    static func mirrored(_ location: ARFaceAnchor.BlendShapeLocation) -> ARFaceAnchor.BlendShapeLocation {
        mirrorTable[location] ?? location
    }

    private static let candidates: [(key: String, location: ARFaceAnchor.BlendShapeLocation)] =
        allLocations.flatMap { [(normalize(displayName($0)), $0), (normalize($0.rawValue), $0)] }

    private static let mirrorTable: [ARFaceAnchor.BlendShapeLocation: ARFaceAnchor.BlendShapeLocation] = {
        let byName = Dictionary(uniqueKeysWithValues: allLocations.map { (displayName($0), $0) })
        return byName.reduce(into: [:]) { table, entry in
            let (name, location) = entry
            if name.hasSuffix("Left"), let other = byName[String(name.dropLast(4)) + "Right"] {
                table[location] = other
                table[other] = location
            }
        }
    }()

    private static func normalize(_ string: String) -> String {
        string.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
