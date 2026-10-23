import simd

nonisolated enum PhoneOrientation: String, Codable, CaseIterable, Identifiable {
    case automatic
    case upright
    case upsideDown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .upright: "Upright"
        case .upsideDown: "Upside down"
        }
    }
}

nonisolated struct PhoneOrientationResolver {
    private(set) var isUpsideDown = false

    mutating func update(mode: PhoneOrientation, gravity: SIMD3<Float>?) {
        switch mode {
        case .upright:
            isUpsideDown = false
        case .upsideDown:
            isUpsideDown = true
        case .automatic:
            // Keep the last pose near horizontal or sideways, where portrait direction is ambiguous.
            if let gravity {
                if gravity.y > 0.5 {
                    isUpsideDown = true
                } else if gravity.y < -0.5 {
                    isUpsideDown = false
                }
            }
        }
    }

    func corrected(rotation: simd_quatf) -> simd_quatf {
        guard isUpsideDown else { return rotation }
        // Change the camera's reference frame, not the face's local axes.
        return simd_quatf(angle: .pi, axis: [0, 0, 1]) * rotation
    }

    func corrected(vector: SIMD3<Float>) -> SIMD3<Float> {
        isUpsideDown ? SIMD3(-vector.x, -vector.y, vector.z) : vector
    }
}
