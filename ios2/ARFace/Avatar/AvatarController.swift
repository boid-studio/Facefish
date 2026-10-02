import ARKit
import Foundation
import OSLog
import RealityKit
import UIKit

/// Drives a loaded avatar's blend shapes and head rotation from `FaceState`.
final class AvatarController {
    let root = Entity()
    /// Mirror mode: the avatar behaves like a reflection of the user.
    var mirrored = true {
        didSet {
            if mirrored != oldValue {
                resetSmoothing()
            }
        }
    }

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
    private var smoothedRotation: simd_quatf?
    private var smoothedBlendShapes: [ARFaceAnchor.BlendShapeLocation: Float] = [:]
    private let logger = Logger(subsystem: "ARFace", category: "Avatar")

    private(set) var boundLocations: Set<ARFaceAnchor.BlendShapeLocation> = []
    private(set) var appliedJawOpen: Float = 0

    /// Approximate mouth position in the "Head" mesh's local space (near the jawOpen blend shape's hinge point).
    private static let mouthLocalPosition: SIMD3<Float> = [0, -0.65, 0.98]
    private static let mouthOpenThreshold: Float = 0.35
    private static let mouthCloseThreshold: Float = 0.15
    private var mouthBubbles: Entity?
    private var mouthIsOpen = false

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

        if let head = model.findEntity(named: "Head") {
            let bubbles = Entity()
            bubbles.position = Self.mouthLocalPosition
            bubbles.components.set(Self.mouthBubbleEmitter())
            head.addChild(bubbles)
            mouthBubbles = bubbles
        }
    }

    func apply(_ state: FaceState?, deltaTime: TimeInterval) {
        guard let state, state.isTracked else {
            resetSmoothing()
            return
        }
        guard deltaTime.isFinite, deltaTime > 0 else { return }
        if deltaTime > 0.25 {
            resetSmoothing()
        }

        let rotation = state.headRotation.vector
        let targetRotation = simd_normalize(mirrored
            ? simd_quatf(vector: [rotation.x, -rotation.y, -rotation.z, rotation.w])
            : state.headRotation)
        let headAlpha = Self.smoothingFactor(deltaTime: deltaTime, timeConstant: 0.04)
        let displayedRotation = smoothedRotation.map {
            simd_slerp($0, targetRotation, headAlpha)
        } ?? targetRotation
        smoothedRotation = displayedRotation
        root.orientation = displayedRotation

        for location in boundLocations.union([.jawOpen]) {
            let source = mirrored ? BlendShapeMapping.mirrored(location) : location
            let targetWeight = state.blendShapes[source] ?? 0
            let timeConstant: TimeInterval
            switch location {
            case .eyeBlinkLeft, .eyeBlinkRight:
                timeConstant = 0.012
            case .jawOpen, .jawForward, .jawLeft, .jawRight,
                 .mouthClose, .mouthFunnel, .mouthPucker:
                timeConstant = 0.02
            default:
                timeConstant = 0.03
            }
            let alpha = Self.smoothingFactor(deltaTime: deltaTime, timeConstant: timeConstant)
            let previousWeight = smoothedBlendShapes[location] ?? targetWeight
            smoothedBlendShapes[location] = previousWeight + alpha * (targetWeight - previousWeight)
        }
        appliedJawOpen = smoothedBlendShapes[.jawOpen] ?? 0
        updateMouthBubbles(jawOpen: appliedJawOpen)

        for target in targets {
            guard var component = target.entity.components[BlendShapeWeightsComponent.self] else { continue }
            for binding in target.bindings {
                component.weightSet[binding.setIndex].weights[binding.weightIndex] = smoothedBlendShapes[binding.location] ?? 0
            }
            target.entity.components.set(component)
        }
    }

    private func resetSmoothing() {
        smoothedRotation = nil
        smoothedBlendShapes.removeAll(keepingCapacity: true)
        mouthIsOpen = false
    }

    /// Fires a small burst of bubbles the moment the mouth opens, with hysteresis to avoid repeat triggers while held open.
    private func updateMouthBubbles(jawOpen: Float) {
        if jawOpen > Self.mouthOpenThreshold, !mouthIsOpen {
            mouthIsOpen = true
            guard var component = mouthBubbles?.components[ParticleEmitterComponent.self] else { return }
            component.burst()
            mouthBubbles?.components.set(component)
        } else if jawOpen < Self.mouthCloseThreshold {
            mouthIsOpen = false
        }
    }

    private static func mouthBubbleEmitter() -> ParticleEmitterComponent {
        var component = ParticleEmitterComponent()
        component.emitterShape = .sphere
        component.emitterShapeSize = [0.015, 0.015, 0.015]
        component.birthLocation = .volume
        component.birthDirection = .world
        component.emissionDirection = [0, 1, 0.5]
        component.speed = 0.1
        component.speedVariation = 0.05
        component.burstCount = 10
        component.burstCountVariation = 4

        var particles = component.mainEmitter
        particles.birthRate = 0
        particles.lifeSpan = 0.8
        particles.lifeSpanVariation = 0.3
        particles.size = 0.006
        particles.sizeVariation = 0.004
        particles.acceleration = [0, 0.05, 0]
        particles.dampingFactor = 0.3
        particles.color = .constant(.single(UIColor(red: 0.85, green: 0.97, blue: 1, alpha: 0.85)))
        particles.opacityCurve = .gradualFadeInOut
        particles.blendMode = .additive
        component.mainEmitter = particles
        return component
    }

    private static func smoothingFactor(deltaTime: TimeInterval, timeConstant: TimeInterval) -> Float {
        Float(1 - exp(-deltaTime / timeConstant))
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
