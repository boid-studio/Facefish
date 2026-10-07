import ARKit
import Foundation
import OSLog
import RealityKit
import UIKit

/// Drives a loaded avatar's blend shapes and head rotation from `FaceState`.
final class AvatarController {
    let sceneRoot = Entity()
    let root = Entity()
    /// Between the head pose (`root`) and the model: carries the swim motion's tilt and rock.
    private let body = Entity()
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
    private var swimMotion = SwimMotion()
    /// How far the fish swims toward where it faces, as a fraction of its size per unit of facing
    /// (looking 20 degrees up moves it about 15% of its size up).
    var headFollowGain: Float = 0.45
    private var followPosition = SIMD3<Float>(repeating: 0)
    private var followVelocity = SIMD3<Float>(repeating: 0)
    private var swimAmount: Float = 1
    private let fishSize: Float
    private var finNeutralRotation: simd_quatf?
    /// Seconds to ease between the rest pose and the tracked face when tracking is lost or found.
    private static let trackingTransitionDuration: TimeInterval = 1.05
    /// 0 = rest pose, 1 = following the face; ramps linearly and is eased when applied.
    private var trackingPresence: Float = 0
    private var lastBlendShapes: [ARFaceAnchor.BlendShapeLocation: Float]?
    private var lastFinAngles: (turn: Float, nod: Float)?

    private(set) var boundLocations: Set<ARFaceAnchor.BlendShapeLocation> = []
    private(set) var appliedJawOpen: Float = 0

    /// The current asset keeps Blender axes in Head: -Y forward, +Z up.
    private static let mouthLocalPosition: SIMD3<Float> = [0, -1.16, -0.43]
    private static let mouthOpenThreshold: Float = 0.35
    private static let mouthCloseThreshold: Float = 0.15
    private var mouthEmitter: Entity?
    private let mouthBubbles = Entity()
    private var mouthBubbleSpheres: BubbleSphereSystem?
    private var mouthIsOpen = false
    private var mouthBubbleBursts: [MouthBubbleBurst] = []
    private var blendShapesEnabled = true
    private var causticsEnabled = true

    init(model: Entity, targetSize: Float = 0.25) {
        finRig = FinRig(model: model)
        eyeRig = EyeRig(model: model)
        lidRig = LidRig(model: model)
        fishSize = targetSize
        fit(model, targetSize: targetSize)
        sceneRoot.addChild(root)
        sceneRoot.addChild(mouthBubbles)
        root.addChild(body)
        body.addChild(model)

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
            mouthEmitter = bubbles
            mouthBubbleSpheres = BubbleSphereSystem(
                parent: mouthBubbles,
                capacity: 64,
                radius: 0.01,
                color: UIColor(red: 0.85, green: 0.97, blue: 1, alpha: 0.85),
                lifeSpan: 2.8,
                lifeVariation: 0.4,
                speed: 0.32,
                speedVariation: 0.07,
                acceleration: [0, 0.21, 0],
                damping: 1.8,
                spawnRadius: [0.008, 0.006, 0.006],
                directionalSpread: 0.55,
                turbulence: 0.035,
                shrinksAtEndOfLife: false
            )
        } else {
            logger.error("Fish model is missing Head; mouth bubble emission is disabled.")
        }
    }

    func apply(_ state: FaceState?, deltaTime: TimeInterval, options: AvatarRenderOptions) {
        guard deltaTime.isFinite, deltaTime > 0 else { return }
        if deltaTime > 0.25 {
            resetSmoothing()
        }

        setBlendShapesEnabled(options.blendShapesEnabled)
        mouthBubbles.isEnabled = options.mouthBubblesEnabled
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
            // Resting face removed, pucker beats funnel, closed lips raise the jaw (FaceCalibration).
            FaceCalibration.shared.feed(state.blendShapes)
            let faceWeights = FaceCalibration.shared.adjusted(state.blendShapes)
            lastBlendShapes = faceWeights
            for location in boundLocations.union([.jawOpen, .mouthFunnel, .mouthClose]) {
                let source = mirrored ? BlendShapeMapping.mirrored(location) : location
                let targetWeight = faceWeights[source] ?? 0
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

        // Once fully at rest, nil hands the fins over to their idle swim.
        let finAngles = presence > 0 ? lastFinAngles : nil
        finRig.update(
            turn: finAngles.map { $0.turn * presence },
            nod: finAngles.map { $0.nod * presence },
            mouthOpen: mouthOpen,
            deltaTime: deltaTime
        )

        updateHeadFollow(enabled: options.headFollowEnabled, deltaTime: Float(min(deltaTime, 0.1)))

        // Swim motion keeps going without tracking, so the fish never freezes; it fades in and out
        // when toggled instead of jumping.
        let swimTarget: Float = options.swimMotionEnabled ? 1 : 0
        swimAmount += (swimTarget - swimAmount) * Self.smoothingFactor(deltaTime: deltaTime, timeConstant: 0.5)
        swimMotion.amount = swimAmount
        let swim = swimMotion.update(deltaTime: Float(min(deltaTime, 0.1)), mouthOpen: mouthOpen, size: fishSize)
        root.position = followPosition + swim.offset   // in the scene's frame, so "up" stays up when the head tilts
        body.orientation = swim.rotation     // relative to the head pose

        if options.mouthBubblesEnabled {
            updateMouthBubbles(jawOpen: appliedJawOpen, deltaTime: Float(min(deltaTime, 0.1)))
            mouthBubbleSpheres?.update(deltaTime: deltaTime)
        } else {
            mouthIsOpen = false
            mouthBubbleBursts.removeAll(keepingCapacity: true)
        }
    }

    /// The fish swims a little toward where it faces: look up and it rises, look aside and it swims
    /// over. It follows on a soft spring (slight overshoot), and drifts back to the middle when the
    /// head is straight or tracking is lost.
    private func updateHeadFollow(enabled: Bool, deltaTime: Float) {
        var target = SIMD3<Float>(repeating: 0)
        if enabled, let rotation = smoothedRotation {
            let facing = rotation.act([0, 0, 1])          // the fish faces +Z at rest
            target = SIMD3(facing.x, facing.y, 0) * headFollowGain * fishSize
            let limit = 0.4 * fishSize                      // stay in the frame
            let length = simd_length(target)
            if length > limit { target *= limit / length }
        }
        let stiffness: Float = 9, ratio: Float = 0.75
        let steps = max(1, Int((deltaTime / (1.0 / 120)).rounded(.up)))
        let stepTime = deltaTime / Float(steps)
        for _ in 0..<steps {
            followVelocity += (stiffness * (target - followPosition) - 2 * ratio * sqrt(stiffness) * followVelocity) * stepTime
            followPosition += followVelocity * stepTime
        }
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
        mouthBubbleBursts.removeAll(keepingCapacity: true)
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

    /// Fires once per mouth opening; bubbles leave the moving fish and rise in scene space.
    private func updateMouthBubbles(jawOpen: Float, deltaTime: Float) {
        if jawOpen > Self.mouthOpenThreshold, !mouthIsOpen {
            mouthIsOpen = true
            mouthBubbleBursts.append(MouthBubbleBurst())
        } else if jawOpen < Self.mouthCloseThreshold {
            mouthIsOpen = false
        }

        guard let mouthEmitter else { return }
        let origin = mouthEmitter.convert(position: .zero, to: mouthBubbles)
        let direction = simd_normalize(mouthEmitter.convert(direction: [0, -1, 0], to: mouthBubbles))
        for index in mouthBubbleBursts.indices {
            for emission in mouthBubbleBursts[index].advance(deltaTime: deltaTime) {
                mouthBubbleSpheres?.emit(
                    count: 1,
                    origin: origin,
                    direction: direction,
                    radiusScale: emission.radiusScale,
                    speedScale: emission.speedScale
                )
            }
        }
        mouthBubbleBursts.removeAll { $0.isComplete }
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
