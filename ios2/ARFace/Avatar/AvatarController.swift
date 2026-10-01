import ARKit
import OSLog
import RealityKit

/// Drives a loaded avatar's blend shapes and head rotation from `FaceState`.
final class AvatarController {
    let root = Entity()
    /// Mirror mode: the avatar behaves like a reflection of the user.
    var mirrored = true

    private struct Binding {
        let setIndex: Int
        let weightIndex: Int
        let location: ARFaceAnchor.BlendShapeLocation
    }

    private struct Target {
        let entity: Entity
        let bindings: [Binding]
    }

    private var targets: [Target] = []
    private let logger = Logger(subsystem: "ARFace", category: "Avatar")

    private(set) var boundLocations: Set<ARFaceAnchor.BlendShapeLocation> = []
    private(set) var appliedJawOpen: Float = 0

    init(model: Entity, targetSize: Float = 0.25) {
        fit(model, targetSize: targetSize)
        root.addChild(model)

        var unmatched: [String] = []
        bind(model, unmatched: &unmatched)
        boundLocations = Set(targets.flatMap { $0.bindings.map(\.location) })
        logger.info("Bound \(self.boundLocations.count)/52 ARKit blend shapes across \(self.targets.count) mesh(es).")
        if !unmatched.isEmpty {
            logger.info("Unmatched model shapes: \(unmatched.joined(separator: ", "))")
        }
    }

    func apply(_ state: FaceState?) {
        guard let state, state.isTracked else { return }

        let q = state.headRotation.vector
        root.orientation = mirrored ? simd_quatf(vector: [q.x, -q.y, -q.z, q.w]) : state.headRotation
        appliedJawOpen = state.blendShapes[.jawOpen] ?? 0

        for target in targets {
            guard var component = target.entity.components[BlendShapeWeightsComponent.self] else { continue }
            for binding in target.bindings {
                let source = mirrored ? BlendShapeMapping.mirrored(binding.location) : binding.location
                component.weightSet[binding.setIndex].weights[binding.weightIndex] = state.blendShapes[source] ?? 0
            }
            target.entity.components.set(component)
        }
    }

    private func bind(_ entity: Entity, unmatched: inout [String]) {
        if let model = entity.components[ModelComponent.self] {
            if !entity.components.has(BlendShapeWeightsComponent.self) {
                let mapping = BlendShapeWeightsMapping(meshResource: model.mesh)
                entity.components.set(BlendShapeWeightsComponent(weightsMapping: mapping))
            }
            if let component = entity.components[BlendShapeWeightsComponent.self], !component.weightSet.isEmpty {
                var bindings: [Binding] = []
                for (setIndex, data) in component.weightSet.enumerated() {
                    for (weightIndex, name) in data.weightNames.enumerated() {
                        if let location = BlendShapeMapping.location(forModelShape: name) {
                            bindings.append(Binding(setIndex: setIndex, weightIndex: weightIndex, location: location))
                        } else {
                            unmatched.append(name)
                        }
                    }
                }
                if !bindings.isEmpty {
                    targets.append(Target(entity: entity, bindings: bindings))
                }
            } else {
                entity.components.remove(BlendShapeWeightsComponent.self)
            }
        }
        for child in entity.children {
            bind(child, unmatched: &unmatched)
        }
    }

    /// Scales the model to `targetSize` and centers it on the root so head rotation pivots around it.
    private func fit(_ model: Entity, targetSize: Float) {
        let bounds = model.visualBounds(relativeTo: nil)
        let size = max(bounds.extents.x, bounds.extents.y, bounds.extents.z)
        guard size > 0 else { return }
        let factor = targetSize / size
        model.scale *= factor
        model.position = (model.position - bounds.center) * factor
    }
}
