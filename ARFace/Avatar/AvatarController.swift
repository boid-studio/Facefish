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
    private let finRig: FinRig
    private let eyeRig: EyeRig
    private let lidRig: LidRig
    private var finNeutralRotation: simd_quatf?
    /// Seconds to ease between the rest pose and the tracked face when tracking is lost or found.
    private static let trackingTransitionDuration: TimeInterval = 1.05
    /// 0 = rest pose, 1 = following the face; ramps linearly and is eased when applied.
    private var trackingPresence: Float = 0
    private var lastBlendShapes: [ARFaceAnchor.BlendShapeLocation: Float]?
    private var lastFinAngles: (turn: Float, nod: Float)?

    private(set) var boundLocations: Set<ARFaceAnchor.BlendShapeLocation> = []
    private(set) var appliedJawOpen: Float = 0

    /// Approximate mouth position in the "Head" mesh's local space (near the jawOpen blend shape's hinge point).
    private static let mouthLocalPosition: SIMD3<Float> = [0, -0.65, 0.98]
    private static let mouthOpenThreshold: Float = 0.35
    private static let mouthCloseThreshold: Float = 0.15
    private var mouthBubbles: Entity?
    private var mouthBubbleSpheres: BubbleSphereSystem?
    private var mouthIsOpen = false
    private var blendShapesEnabled = true
    private var causticsEnabled = true

    init(model: Entity, targetSize: Float = 0.25) {
        finRig = FinRig(model: model)
        eyeRig = EyeRig(model: model)
        lidRig = LidRig(model: model)
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
            head.addChild(bubbles)
            mouthBubbles = bubbles
            mouthBubbleSpheres = BubbleSphereSystem(
                parent: bubbles,
                capacity: 24,
                radius: 0.006,
                color: UIColor(red: 0.85, green: 0.97, blue: 1, alpha: 0.85),
                lifeSpan: 0.8,
                lifeVariation: 0.3,
                speed: 0.1,
                speedVariation: 0.05,
                acceleration: [0, 0.05, 0],
                damping: 0.3,
                spawnRadius: [0.015, 0.015, 0.015]
            )
        }
    }

    func apply(_ state: FaceState?, deltaTime: TimeInterval, options: AvatarRenderOptions) {
        guard deltaTime.isFinite, deltaTime > 0 else { return }
        if deltaTime > 0.25 {
            resetSmoothing()
        }

        setBlendShapesEnabled(options.blendShapesEnabled)
        mouthBubbles?.isEnabled = options.mouthBubblesEnabled
        let causticsChanged = options.causticsEnabled != causticsEnabled
        causticsEnabled = options.causticsEnabled
        finRig.setEnabled(options.finAnimationEnabled, refreshMaterials: causticsChanged)
        eyeRig.setEnabled(options.eyeMovementEnabled)
        lidRig.setEnabled(options.eyelidsEnabled)

        // Tracking on/off eases between the rest pose and the live face instead of snapping.
        let isTracked = state?.isTracked == true
        let presenceStep = Float(deltaTime / Self.trackingTransitionDuration)
        trackingPresence = isTracked
            ? min(1, trackingPresence + presenceStep)
            : max(0, trackingPresence - presenceStep)
        let presence = Self.smootherstep(trackingPresence)
        if presence == 0, !isTracked {
            // Fully at rest: recalibrate the fins' neutral head pose on the next tracked frame.
            finNeutralRotation = nil
            lastFinAngles = nil
        }

        if let state, isTracked {
            let rotation = state.headRotation.vector
            let targetRotation = simd_normalize(mirrored
                ? simd_quatf(vector: [rotation.x, -rotation.y, -rotation.z, rotation.w])
                : state.headRotation)
            let headAlpha = Self.smoothingFactor(deltaTime: deltaTime, timeConstant: 0.04)
            smoothedRotation = smoothedRotation.map {
                simd_slerp($0, targetRotation, headAlpha)
            } ?? targetRotation

            lastFinAngles = finAngles(for: state.headRotation)
            lastBlendShapes = state.blendShapes
            for location in boundLocations.union([.jawOpen, .mouthFunnel, .mouthClose]) {
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
        }

        // Without tracking, the last tracked pose stays as the "live" end of the blend while it fades out.
        root.orientation = smoothedRotation.map {
            simd_slerp(simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), $0, presence)
        } ?? simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)

        if let blendShapes = lastBlendShapes {
            let mirrored = self.mirrored
            let weight: (ARFaceAnchor.BlendShapeLocation) -> Float = {
                (blendShapes[mirrored ? BlendShapeMapping.mirrored($0) : $0] ?? 0) * presence
            }
            eyeRig.update(weight: weight, deltaTime: deltaTime)
            lidRig.update(weight: weight, deltaTime: deltaTime)
        } else {
            eyeRig.update(weight: nil, deltaTime: deltaTime)
            lidRig.update(weight: nil, deltaTime: deltaTime)
        }

        appliedJawOpen = (smoothedBlendShapes[.jawOpen] ?? 0) * presence
        let mouthFunnel = (smoothedBlendShapes[.mouthFunnel] ?? 0) * presence
        let mouthClose = (smoothedBlendShapes[.mouthClose] ?? 0) * presence
        let mouthOpen = max(appliedJawOpen, 0.5 * mouthFunnel) * (1 - 0.85 * mouthClose)
        if options.mouthBubblesEnabled {
            updateMouthBubbles(jawOpen: appliedJawOpen)
        }

        if blendShapesEnabled {
            for target in targets {
                guard var component = target.entity.components[BlendShapeWeightsComponent.self] else { continue }
                for binding in target.bindings {
                    component.weightSet[binding.setIndex].weights[binding.weightIndex] =
                        (smoothedBlendShapes[binding.location] ?? 0) * presence
                }
                target.entity.components.set(component)
            }
        }

        if options.mouthBubblesEnabled {
            mouthBubbleSpheres?.update(deltaTime: deltaTime)
        }
        // Once fully at rest, nil hands the fins over to their idle swim.
        let finAngles = presence > 0 ? lastFinAngles : nil
        finRig.update(
            turn: finAngles.map { $0.turn * presence },
            nod: finAngles.map { $0.nod * presence },
            mouthOpen: mouthOpen,
            deltaTime: deltaTime
        )
    }

    /// Ease-in-out with zero velocity and acceleration at both ends.
    private static func smootherstep(_ x: Float) -> Float {
        x * x * x * (x * (x * 6 - 15) + 10)
    }

    private func setBlendShapesEnabled(_ enabled: Bool) {
        guard enabled != blendShapesEnabled else { return }
        blendShapesEnabled = enabled
        guard !enabled else { return }

        for target in targets {
            guard var component = target.entity.components[BlendShapeWeightsComponent.self] else { continue }
            for binding in target.bindings {
                component.weightSet[binding.setIndex].weights[binding.weightIndex] = 0
            }
            target.entity.components.set(component)
        }
    }

    private func resetSmoothing() {
        smoothedRotation = nil
        smoothedBlendShapes.removeAll(keepingCapacity: true)
        mouthIsOpen = false
        finNeutralRotation = nil
    }

    private func finAngles(for headRotation: simd_quatf) -> (Float, Float) {
        guard let finNeutralRotation else {
            self.finNeutralRotation = headRotation
            return (0, 0)
        }

        let relativeRotation = simd_normalize(simd_mul(simd_inverse(finNeutralRotation), headRotation))
        let imaginary = relativeRotation.imag
        let imaginaryLength = simd_length(imaginary)
        let angle = 2 * atan2(imaginaryLength, relativeRotation.real)
        let turnSign: Float = mirrored ? -1 : 1
        let maximumAngle: Float = 55 * .pi / 180
        let turn = imaginaryLength > 1e-6 ? angle * imaginary.y / imaginaryLength : 0
        let nod = imaginaryLength > 1e-6 ? angle * imaginary.x / imaginaryLength : 0
        return (
            min(max(turn, -maximumAngle), maximumAngle) * turnSign,
            min(max(nod, -maximumAngle), maximumAngle)
        )
    }

    /// Fires a small burst of bubbles the moment the mouth opens, with hysteresis to avoid repeat triggers while held open.
    private func updateMouthBubbles(jawOpen: Float) {
        if jawOpen > Self.mouthOpenThreshold, !mouthIsOpen {
            mouthIsOpen = true
            mouthBubbleSpheres?.emit(count: 10 + Int.random(in: 0...4))
        } else if jawOpen < Self.mouthCloseThreshold {
            mouthIsOpen = false
        }
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
                            guard !Self.isEyelidBlink(location) else { continue }
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

    private static func isEyelidBlink(_ location: ARFaceAnchor.BlendShapeLocation) -> Bool {
        location == .eyeBlinkLeft || location == .eyeBlinkRight
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
