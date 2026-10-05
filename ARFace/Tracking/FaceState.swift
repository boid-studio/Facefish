import ARKit

nonisolated struct FaceState: Sendable {
    var isTracked: Bool
    var blendShapes: [ARFaceAnchor.BlendShapeLocation: Float]
    /// Head orientation relative to the camera; identity when facing the device.
    var headRotation: simd_quatf

    init(anchor: ARFaceAnchor, cameraTransform: simd_float4x4) {
        isTracked = anchor.isTracked
        blendShapes = anchor.blendShapes.mapValues(\.floatValue)
        headRotation = simd_quatf(simd_inverse(cameraTransform) * anchor.transform)
    }
}
