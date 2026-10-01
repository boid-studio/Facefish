import ARKit

nonisolated struct FaceState: Sendable {
    var isTracked: Bool
    var blendShapes: [ARFaceAnchor.BlendShapeLocation: Float]
    /// Head orientation in gravity-aligned world space; identity when facing the device.
    var headRotation: simd_quatf

    init(anchor: ARFaceAnchor) {
        isTracked = anchor.isTracked
        blendShapes = anchor.blendShapes.mapValues(\.floatValue)
        headRotation = simd_quatf(anchor.transform)
    }
}
