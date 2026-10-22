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
    /// Looking around and blowing bubbles while there's no face (IdleLife.swift).
    private var idleLife = IdleLife()
    private var idleYaw: Float = 0
    private var idleBubbleBacklog: Float = 0
    /// Laughter in the face and voice (LaughDetector.swift), played bigger on the fish.
    private var laugh = LaughDetector()
    private var lastLaughPulse: Float = 0
    private var laughReadoutTime: Float = 0
    /// This frame's laugh (0...1), for the face.
    private var laughing: Float = 0
    /// Singing a big note (loud voice, open mouth), 0...1, and the vibrato's clock.
    private var bigNoteLevel: Float = 0
    private var bigNote: Float = 0
    private var vibratoTime: Float = 0
    private var lastMouthOpen: Float = 0
    /// A move taking over the mouth (blowing bubbles), from the last frame's move.
    private var moveFace: (takeover: Float, cheekPuff: Float, pucker: Float, bubbles: Float) = (0, 0, 0, 0)
    /// 0 = natural, 1 = big stage acting (AvatarDebugModel.acting, also set from the control app).
    private var acting: Float { AvatarSession.shared.avatarDebug.acting }
    /// A lap around the bowl (SwimAround.swift) and the quick moves (SwimTrick.swift).
    private var swimAround = SwimAround()
    private var activeTrick: SwimTrick?
    private var lastTrickAngles: (yaw: Float, pitch: Float) = (0, 0)
    private var swimFacing = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    /// The lap facing's yaw (radians, kept continuous), how fast it turns, and where the fins steer.
    private var facingYaw: Float = 0
    private var facingTurnRate: Float = 0
    private var swimSteer: Float = 0
    /// Where quick moves shed bubbles: the tail and side fins, in the swimming body's frame.
    private var wakeSpots: [BoundingBox] = []
    private var wakeBubbleBacklog: Float = 0
    private var appliedBend: Float = 0
    private var appliedBlush: Float = 0
    private var headEntity: Entity?
    private var tailRig: (entity: Entity, rest: float4x4)?
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
    /// Loud lows with the mouth at least this open stream big bubbles.
    static let audioBigBubbleLowThreshold: Float = 0.3
    static let audioBigBubbleMouthThreshold: Float = 0.3
    /// Loud highs stream small bubbles.
    static let audioSmallBubbleHighThreshold: Float = 0.45
    private var audioBigBubbleBacklog: Float = 0
    private var audioSmallBubbleBacklog: Float = 0
    private var blendShapesEnabled = true
    private var causticsEnabled = true

    var glassSpheres: [SIMD4<Float>] { mouthBubbleSpheres?.glassSpheres ?? [] }

    init(model: Entity, targetSize: Float = 0.25, screenSpaceGlass: Bool = false) {
        finRig = FinRig(model: model)
        eyeRig = EyeRig(model: model)
        lidRig = LidRig(model: model)
        fishSize = targetSize
        fit(model, targetSize: targetSize)
        headEntity = model.findEntity(named: "Head")
        if let tail = model.findEntity(named: "TailRig") {
            tailRig = (tail, tail.transform.matrix)
        }
        sceneRoot.addChild(root)
        sceneRoot.addChild(mouthBubbles)
        root.addChild(body)
        body.addChild(model)
        // The tail twice, so half the wake comes off it.
        wakeSpots = ["TailRig", "TailRig", "PecRig_L", "PecRig_R"].compactMap { name in
            model.findEntity(named: name).map { $0.visualBounds(relativeTo: body) }
        }

        var unmatched: [String] = []
        bind(model, unmatched: &unmatched)
        boundLocations = Set(targets.flatMap { $0.bindings.map(\.location) })

        if let head = model.findEntity(named: "Head") {
            let bubbles = Entity()
            bubbles.position = Self.mouthLocalPosition
            head.addChild(bubbles)
            mouthEmitter = bubbles
            mouthBubbleSpheres = BubbleSphereSystem(
                parent: mouthBubbles,
                capacity: 160,
                radius: 0.01,
                color: UIColor(red: 0.85, green: 0.97, blue: 1, alpha: 0.85),
                lifeSpan: 2.8,
                lifeVariation: 0.4,
                speed: 0.32,
                speedVariation: 0.07,
                acceleration: BubbleSphereSystem.risingAcceleration,
                damping: BubbleSphereSystem.risingDamping,
                spawnRadius: [0.008, 0.006, 0.006],
                directionalSpread: 0.55,
                turbulence: BubbleSphereSystem.risingTurbulence,
                shrinksAtEndOfLife: false,
                screenSpaceGlass: screenSpaceGlass
            )
        } else {
            logger.error("Fish model is missing Head; mouth bubble emission is disabled.")
        }
    }

    func apply(_ state: FaceState?, audio: AudioLevels = .silent, deltaTime: TimeInterval, options: AvatarRenderOptions) {
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

        // Waiting for a face: the fish looks around and blows bubbles, as much as the face is gone.
        let idleWeight = 1 - presence
        let idle = idleLife.update(deltaTime: Float(min(deltaTime, 0.1)), waiting: !isTracked, weight: idleWeight)
        let idleRotation = simd_quatf(angle: idle.yaw, axis: [0, 1, 0])
            * simd_quatf(angle: idle.pitch, axis: [1, 0, 0])
            * simd_quatf(angle: idle.roll, axis: [0, 0, 1])
        let idleTurnRate = (idle.yaw * idleWeight - idleYaw) / Float(min(deltaTime, 0.1))
        idleYaw = idle.yaw * idleWeight

        // Without tracking, the last tracked pose stays as the "live" end of the blend while it fades out.
        // Acting bigger turns the head further than the performer does.
        let headGain = 1 + 0.8 * acting
        root.orientation = smoothedRotation.map {
            simd_slerp(idleRotation, Self.amplified($0, by: headGain), presence)
        } ?? idleRotation

        // Laughing: the fish laughs bigger (see laughed(_:_:)), in time with each "ha".
        let frameDelta = Float(min(deltaTime, 0.1))
        laugh.update(weights: isTracked ? lastBlendShapes : nil, voice: audio.overall, deltaTime: frameDelta)
        laughing = laugh.intensity * presence

        // Singing a big note: a loud voice through an open mouth. Played bigger with Acting.
        let note = isTracked ? Self.smoothstep(0.35, 0.7, audio.overall) * Self.smoothstep(0.15, 0.4, lastMouthOpen) : 0
        bigNoteLevel += (note - bigNoteLevel) * (1 - exp(-frameDelta / (note > bigNoteLevel ? 0.25 : 0.5)))
        bigNote = bigNoteLevel * presence * (0.3 + 0.7 * acting)
        vibratoTime += frameDelta
        publishLaughReadout(deltaTime: frameDelta)

        let eyeRange = eyeRig.range
        if let blendShapes = lastBlendShapes {
            let mirrored = self.mirrored
            let weight: (ARFaceAnchor.BlendShapeLocation) -> Float = { [self] location in
                played(location, (blendShapes[mirrored ? BlendShapeMapping.mirrored(location) : location] ?? 0) * presence)
                    + idle.weight(location, eyeRange: eyeRange) * idleWeight
            }
            eyeRig.update(weight: weight, deltaTime: deltaTime)
            lidRig.update(weight: weight, deltaTime: deltaTime)
        } else {
            let weight: (ARFaceAnchor.BlendShapeLocation) -> Float = { idle.weight($0, eyeRange: eyeRange) }
            eyeRig.update(weight: weight, deltaTime: deltaTime)
            lidRig.update(weight: weight, deltaTime: deltaTime)
        }

        appliedJawOpen = (smoothedBlendShapes[.jawOpen] ?? 0) * presence
        let mouthFunnel = (smoothedBlendShapes[.mouthFunnel] ?? 0) * presence
        let mouthClose = (smoothedBlendShapes[.mouthClose] ?? 0) * presence
        let mouthOpen = max(appliedJawOpen, 0.5 * mouthFunnel) * (1 - 0.85 * mouthClose)
        lastMouthOpen = mouthOpen
        if blendShapesEnabled {
            for target in targets {
                guard var component = target.entity.components[BlendShapeWeightsComponent.self] else { continue }
                for binding in target.bindings {
                    component.weightSet[binding.setIndex].weights[binding.weightIndex] =
                        played(binding.location, (smoothedBlendShapes[binding.location] ?? 0) * presence)
                        + idle.weight(binding.location, eyeRange: eyeRange) * idleWeight
                }
                target.entity.components.set(component)
            }
        }

        // Moves: a lap around the bowl (facing along the path) or a quick spin or loop (on top of
        // the live pose). The fins steer and push, the body bends.
        let moveDelta = Float(min(deltaTime, 0.1))
        let liveOrientation = root.orientation
        if let move = nextMove() {
            start(move, live: liveOrientation)
        }
        var bodyTurnRate: Float = 0, bodyNodRate: Float = 0, steer: Float = 0, effort: Float = 0, bend: Float = 0
        var cover = SIMD2<Float>(repeating: 0), blush: Float = 0
        let lap = swimAround.update(deltaTime: moveDelta)
        let lapWeight = lap?.weight ?? 0
        if let lap {
            updateSwimFacing(lap, deltaTime: moveDelta)
            root.orientation = simd_slerp(liveOrientation, swimFacing, lapWeight)
            bodyTurnRate = facingTurnRate * lapWeight
            steer = swimSteer * lapWeight
            effort = lap.effort * lapWeight
            bend = (0.075 + 0.105 * lap.speed) * lapWeight
        }
        var trickOffset = SIMD3<Float>(repeating: 0)
        if activeTrick != nil {
            if let pose = activeTrick?.update(deltaTime: moveDelta) {
                root.orientation = liveOrientation * pose.rotation
                trickOffset = liveOrientation.act(pose.offset)
                bodyTurnRate = (pose.yaw - lastTrickAngles.yaw) / moveDelta
                bodyNodRate = (pose.pitch - lastTrickAngles.pitch) / moveDelta
                lastTrickAngles = (pose.yaw, pose.pitch)
                if options.mouthBubblesEnabled {
                    updateWakeBubbles(turnSpeed: simd_length(SIMD2(bodyTurnRate, bodyNodRate)), deltaTime: moveDelta)
                }
                steer = pose.steer
                effort = pose.effort
                bend = pose.bend
                cover = pose.cover
                blush = pose.blush
                moveFace = (pose.mouthTakeover, pose.cheekPuff, pose.pucker, pose.bubbles)
            } else {
                activeTrick = nil
            }
        }
        if activeTrick == nil { moveFace = (0, 0, 0, 0) }
        finRig.bodyTurnRate = bodyTurnRate + idleTurnRate
        finRig.bodyNodRate = bodyNodRate
        finRig.steer = steer
        finRig.propulsion = max(effort, 0.45 * laughing)      // laughing: the tail wags, fins paddle
        let vibrato = sin(2 * .pi * 5.5 * vibratoTime)
        finRig.clap = laughing * laugh.pulse                  // and the side fins clap on each "ha"
            + 0.12 * bigNote * vibrato                        // a shimmer on a held note
        finRig.spread = bigNote                               // big notes: fins open wide
        finRig.finReaction = 1 + acting
        finRig.cover = cover
        lidRig.maxClosed = 1 - 0.95 * cover
        applyFaceShader(bend: bend, blush: max(blush, 0.3 * laughing))

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
        swimMotion.amount = swimAmount * (1 + 0.8 * idleWeight)   // livelier while waiting
        let swim = swimMotion.update(deltaTime: Float(min(deltaTime, 0.1)), mouthOpen: mouthOpen, size: fishSize)
        // Laughing: head thrown back a little, bouncing and rocking on each "ha".
        let laughBounce = laughing * laugh.pulse
        root.position = followPosition * (1 - lapWeight) + swim.offset + (lap?.position ?? .zero) * lapWeight + trickOffset
            + SIMD3<Float>(0, 0.008 * laughBounce + 0.004 * laughing, 0)
        // Big notes: head back, a vibrato tremble, the body swelling a little.
        body.orientation = swim.rotation     // relative to the head pose
            * simd_quatf(angle: -0.12 * laughing - 0.07 * laughBounce - 0.15 * bigNote, axis: [1, 0, 0])
            * simd_quatf(angle: 0.05 * laughBounce + 0.025 * bigNote * vibrato, axis: [0, 0, 1])
        body.scale = SIMD3(repeating: 1 + 0.04 * bigNote)

        if options.mouthBubblesEnabled {
            updateMouthBubbles(jawOpen: appliedJawOpen, deltaTime: Float(min(deltaTime, 0.1)))
            if options.audioBubblesEnabled {
                updateAudioBubbles(audio: audio, mouthOpen: mouthOpen, deltaTime: Float(min(deltaTime, 0.1)))
            } else {
                resetAudioBubbles()
            }
            updateIdleBubbles(rate: idle.bubbles * idleWeight + moveFace.bubbles, deltaTime: Float(min(deltaTime, 0.1)))
            // A little puff of bubbles on each "ha".
            if laughing > 0.4, laugh.pulse > 0.5, lastLaughPulse <= 0.5, let mouthEmitter {
                let origin = mouthEmitter.convert(position: .zero, to: mouthBubbles)
                let direction = simd_normalize(mouthEmitter.convert(direction: [0, -1, 0], to: mouthBubbles))
                for _ in 0..<Int.random(in: 3...6) {
                    mouthBubbleSpheres?.emit(count: 1, origin: origin, direction: direction,
                                             radiusScale: Float.random(in: 0.15...0.45), speedScale: Float.random(in: 0.3...0.7))
                }
            }
            lastLaughPulse = laugh.pulse
            mouthBubbleSpheres?.update(deltaTime: deltaTime)
        } else {
            lastLaughPulse = 0
            mouthIsOpen = false
            mouthBubbleBursts.removeAll(keepingCapacity: true)
            resetAudioBubbles()
        }
    }

    /// The face as the fish plays it: acted bigger, laughing, singing big notes, and a move taking
    /// over the mouth (blowing bubbles).
    private func played(_ location: ARFaceAnchor.BlendShapeLocation, _ value: Float) -> Float {
        blown(location, sung(location, laughed(location, acted(location, value), laughing)))
    }

    /// Acting bigger: every expression pushed toward its full shape (a small one grows up to 2.5x),
    /// except where the eyes look, blinks, and the lip seal.
    private func acted(_ location: ARFaceAnchor.BlendShapeLocation, _ value: Float) -> Float {
        guard acting > 0, value > 0 else { return value }
        switch location {
        case .eyeBlinkLeft, .eyeBlinkRight, .mouthClose,
             .eyeLookUpLeft, .eyeLookUpRight, .eyeLookDownLeft, .eyeLookDownRight,
             .eyeLookInLeft, .eyeLookInRight, .eyeLookOutLeft, .eyeLookOutRight:
            return value
        default:
            return 1 - pow(1 - min(value, 1), 1 + 1.5 * acting)
        }
    }

    /// Big notes: brows up, eyes wide, the mouth opening a little more.
    private func sung(_ location: ARFaceAnchor.BlendShapeLocation, _ value: Float) -> Float {
        guard bigNote > 0 else { return value }
        switch location {
        case .browInnerUp, .browOuterUpLeft, .browOuterUpRight: return value + bigNote * 0.5 * (1 - value)
        case .eyeWideLeft, .eyeWideRight: return value + bigNote * 0.4 * (1 - value)
        case .jawOpen: return value + bigNote * 0.15 * (1 - value)
        default: return value
        }
    }

    /// A move taking over the mouth: puffed cheeks and puckered lips, the rest of the mouth at rest.
    private func blown(_ location: ARFaceAnchor.BlendShapeLocation, _ value: Float) -> Float {
        let takeover = moveFace.takeover
        guard takeover > 0 else { return value }
        switch location {
        case .cheekPuff: return value * (1 - takeover) + moveFace.cheekPuff * takeover
        case .mouthPucker: return value * (1 - takeover) + moveFace.pucker * takeover
        default:
            let name = location.rawValue
            return name.hasPrefix("mouth") || name.hasPrefix("jaw") || name.hasPrefix("tongue")
                ? value * (1 - takeover) : value
        }
    }

    /// A head turn made bigger (`gain` times the angle, up to about 70 degrees).
    private static func amplified(_ rotation: simd_quatf, by gain: Float) -> simd_quatf {
        guard gain != 1 else { return rotation }
        var angle = rotation.angle, axis = rotation.axis
        if angle > .pi { angle = 2 * .pi - angle; axis = -axis }
        guard angle > 1e-5 else { return rotation }
        return simd_quatf(angle: min(angle * gain, 1.2), axis: axis)
    }

    private static func smoothstep(_ from: Float, _ to: Float, _ x: Float) -> Float {
        let t = min(max((x - from) / (to - from), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Laughing pushes the face further: a wider smile, cheeks up, squeezed "happy" eyes, brows up,
    /// lips apart, and the jaw dropping further on each "ha". `amount` 0...1 is how hard it laughs.
    private func laughed(_ location: ARFaceAnchor.BlendShapeLocation, _ value: Float, _ amount: Float) -> Float {
        guard amount > 0 else { return value }
        switch location {
        case .mouthSmileLeft, .mouthSmileRight: return value + amount * 0.6 * (1 - value)
        case .cheekSquintLeft, .cheekSquintRight: return value + amount * 0.7 * (1 - value)
        case .eyeBlinkLeft, .eyeBlinkRight: return value + amount * 0.55 * (1 - value)
        case .eyeSquintLeft, .eyeSquintRight: return value + amount * 0.6 * (1 - value)
        case .browInnerUp: return value + amount * 0.35 * (1 - value)
        case .jawOpen: return min(1, value + amount * (0.1 + 0.35 * max(0, laugh.pulse)))
        case .mouthClose: return value * (1 - amount)
        default: return value
        }
    }

    /// The laugh detector's numbers for the debug panel, a few times a second.
    private func publishLaughReadout(deltaTime: Float) {
        laughReadoutTime += deltaTime
        guard laughReadoutTime >= 0.25 else { return }
        laughReadoutTime = 0
        AvatarSession.shared.avatarDebug.laughReadout = LaughReadout(
            intensity: laugh.intensity, smile: laugh.smile, squint: laugh.squint,
            jawRhythm: laugh.jawRhythm, voiceRhythm: laugh.voiceRhythm, bigNote: bigNote
        )
    }

    /// The next move asked for in AvatarSession. Asks while a move is running are dropped.
    private func nextMove() -> SwimMove? {
        let session = AvatarSession.shared
        guard !session.pendingMoves.isEmpty else { return nil }
        let move = session.pendingMoves.removeFirst()
        return swimAround.isActive || activeTrick != nil ? nil : move
    }

    /// Starts a move from the fish's pose now (`live`). It goes off to the side the fish already
    /// faces, or either way when it faces straight out.
    private func start(_ move: SwimMove, live: simd_quatf) {
        let forward = live.act([0, 0, 1])
        let side: Float = abs(forward.x) > 0.12 ? (forward.x > 0 ? 1 : -1) : (Bool.random() ? 1 : -1)
        switch move {
        case .lap:
            swimAround.start(from: followPosition, side: side)
            swimFacing = live
            facingYaw = atan2(forward.x, forward.z)
            facingTurnRate = 0
        case .spin:
            activeTrick = SwimTrick(kind: .spin, direction: side)
        case .loop:
            activeTrick = SwimTrick(kind: .loop, direction: side)
        case .blush:
            activeTrick = SwimTrick(kind: .blush, direction: side)
        case .bubbles:
            activeTrick = SwimTrick(kind: .bubbles, direction: side)
        }
        lastTrickAngles = (0, 0)
    }

    /// Turns the fish to face along the lap (it faces +Z at rest), nose following climbs and
    /// dives a little, banking into turns and rolling off level now and then. The body follows a
    /// beat late; the fins steer toward where the path goes next, so they work before it turns.
    private func updateSwimFacing(_ lap: SwimAround.Pose, deltaTime: Float) {
        // Yaw of a direction, kept continuous with the facing so a half turn doesn't flip sides.
        func yaw(of direction: SIMD3<Float>) -> Float {
            var angle = atan2(direction.x, direction.z)
            while angle - facingYaw > .pi { angle -= 2 * .pi }
            while angle - facingYaw < -.pi { angle += 2 * .pi }
            return angle
        }
        let pitch = -asin(min(max(lap.heading.y, -1), 1)) * 0.6
        let bank = min(max(-facingTurnRate * 0.16, -0.6), 0.6)
        let target = simd_quatf(angle: yaw(of: lap.heading), axis: [0, 1, 0])
            * simd_quatf(angle: pitch, axis: [1, 0, 0])
            * simd_quatf(angle: bank + lap.roll, axis: [0, 0, 1])
        swimFacing = simd_slerp(swimFacing, target, (1 - exp(-deltaTime / 0.22)) * lap.bodyFollow)
        let newYaw = yaw(of: swimFacing.act([0, 0, 1]))
        let rate = (newYaw - facingYaw) / max(deltaTime, 1e-3)
        facingYaw = newYaw
        facingTurnRate += (rate - facingTurnRate) * (1 - exp(-deltaTime / 0.08))
        swimSteer = min(max((yaw(of: lap.ahead) - facingYaw) / 0.8, -1), 1)
    }

    /// The fish swims a little toward where it faces: look up and it rises, look aside and it swims
    /// over. It follows on a soft spring (slight overshoot), and drifts back to the middle when the
    /// head is straight or tracking is lost.

    /// The body wave while swimming (faceBodyBend in Underwater.metal) with the tail fin riding on
    /// the bent tail stalk, and the cheeks' blush (faceCausticSurface). `bend` is the bend at the
    /// tail in mesh units, 0 straightens it; `blush` 0...1.
    private func applyFaceShader(bend amount: Float, blush: Float) {
        let blush = blush > 0.002 ? blush : 0
        guard amount > 0.0005 || appliedBend > 0 || blush != appliedBlush else { return }
        appliedBend = amount > 0.0005 ? amount : 0
        appliedBlush = blush
        let phase = finRig.strokePhase
        if let headEntity, var model = headEntity.components[ModelComponent.self] {
            model.materials = model.materials.map { current in
                guard var material = current as? CustomMaterial else { return current }
                material.custom.value.x = appliedBend
                material.custom.value.y = phase
                material.custom.value.w = blush
                return material
            }
            headEntity.components.set(model)
        }
        // Same wave as the shader at the tail stalk (mesh y = 0.704, Blender axes): move the tail
        // rig sideways and turn it with the body's slope there.
        if let tailRig {
            let y: Float = 0.704
            let w = min(max((y - 0.1) / 0.62, 0), 1)
            let weight = pow(w * w * (3 - 2 * w), 2)
            let offset = appliedBend * weight * sin(phase - 3.2 * y)
            let slope = appliedBend * weight * -3.2 * cos(phase - 3.2 * y)
            let pivot = SIMD3<Float>(0, 0.704, -0.323)
            let turn = simd_float4x4(simd_quatf(angle: -atan(slope), axis: [0, 0, 1]))
            var move = matrix_identity_float4x4
            move.columns.3 = SIMD4(pivot + SIMD3(offset, 0, 0), 1)
            var back = matrix_identity_float4x4
            back.columns.3 = SIMD4(-pivot, 1)
            tailRig.entity.transform = Transform(matrix: move * turn * back * tailRig.rest)
        }
    }

    private func updateHeadFollow(enabled: Bool, deltaTime: Float) {
        var target = SIMD3<Float>(repeating: 0)
        if enabled, let rotation = smoothedRotation {
            let facing = rotation.act([0, 0, 1])          // the fish faces +Z at rest
            target = SIMD3(facing.x, facing.y, 0) * headFollowGain * (1 + acting) * fishSize
            let limit = (0.4 + 0.15 * acting) * fishSize    // stay in the frame
            let length = simd_length(target)
            if length > limit { target *= limit / length }
        }
        let stiffness: Float = 9, ratio: Float = 0.75
        let steps = max(1, Int((deltaTime / (1.0 / 120)).rounded(.up)))
        let stepTime = deltaTime / Float(steps)
        for _ in 0..<steps {
            let springForce: SIMD3<Float> = stiffness * (target - followPosition)
            let damping: Float = 2 * ratio * sqrt(stiffness)
            let dampingForce: SIMD3<Float> = damping * followVelocity
            followVelocity += (springForce - dampingForce) * stepTime
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
        resetAudioBubbles()
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

    /// Streams bubbles from the mouth while the microphone is loud: big ones for strong lows with the
    /// mouth open, small ones for strong highs. Louder sound streams faster.
    private func updateAudioBubbles(audio: AudioLevels, mouthOpen: Float, deltaTime: Float) {
        guard let mouthEmitter, let mouthBubbleSpheres else { return }

        func stream(
            _ backlog: inout Float,
            level: Float,
            threshold: Float,
            rate: ClosedRange<Float>
        ) -> Int {
            guard level > threshold else {
                backlog = 0
                return 0
            }
            let excess = (level - threshold) / (1 - threshold)
            backlog += (rate.lowerBound + excess * (rate.upperBound - rate.lowerBound)) * deltaTime
            let count = Int(backlog)
            backlog -= Float(count)
            return count
        }

        let bigCount = stream(
            &audioBigBubbleBacklog,
            level: mouthOpen > Self.audioBigBubbleMouthThreshold ? audio.low : 0,
            threshold: Self.audioBigBubbleLowThreshold,
            rate: 6...16
        )
        let smallCount = stream(
            &audioSmallBubbleBacklog,
            level: audio.high,
            threshold: Self.audioSmallBubbleHighThreshold,
            rate: 15...45
        )
        guard bigCount + smallCount > 0 else { return }

        let origin = mouthEmitter.convert(position: .zero, to: mouthBubbles)
        let direction = simd_normalize(mouthEmitter.convert(direction: [0, -1, 0], to: mouthBubbles))
        for _ in 0..<bigCount {
            mouthBubbleSpheres.emit(
                count: 1,
                origin: origin,
                direction: direction,
                radiusScale: Float.random(in: 0.7...1.0),
                speedScale: Float.random(in: 0.15...0.3)
            )
        }
        for _ in 0..<smallCount {
            mouthBubbleSpheres.emit(
                count: 1,
                origin: origin,
                direction: direction,
                radiusScale: Float.random(in: 0.1...0.22),
                speedScale: Float.random(in: 0.2...0.5)
            )
        }
    }

    /// A stream of bubbles blown through puckered lips while waiting for a face (IdleLife).
    private func updateIdleBubbles(rate: Float, deltaTime: Float) {
        guard let mouthEmitter, let mouthBubbleSpheres, rate > 0 else {
            idleBubbleBacklog = 0
            return
        }
        idleBubbleBacklog += rate * deltaTime
        let count = Int(idleBubbleBacklog)
        idleBubbleBacklog -= Float(count)
        guard count > 0 else { return }
        let origin = mouthEmitter.convert(position: .zero, to: mouthBubbles)
        let direction = simd_normalize(mouthEmitter.convert(direction: [0, -1, 0], to: mouthBubbles))
        for _ in 0..<count {
            mouthBubbleSpheres.emit(
                count: 1,
                origin: origin,
                direction: direction,
                radiusScale: Float.random(in: 0.15...0.55),
                speedScale: Float.random(in: 0.5...0.9)
            )
        }
    }

    /// Bubbles shed by the tail and side fins in a quick move, more the faster the fish turns,
    /// flung outward and left behind to rise.
    private func updateWakeBubbles(turnSpeed: Float, deltaTime: Float) {
        guard let mouthBubbleSpheres, !wakeSpots.isEmpty, turnSpeed > 2 else {
            wakeBubbleBacklog = 0
            return
        }
        wakeBubbleBacklog += min(turnSpeed, 25) * 3 * deltaTime
        let count = Int(wakeBubbleBacklog)
        wakeBubbleBacklog -= Float(count)
        let center = body.convert(position: .zero, to: mouthBubbles)
        for _ in 0..<count {
            guard let spot = wakeSpots.randomElement() else { return }
            let local = SIMD3<Float>(
                Float.random(in: spot.min.x...spot.max.x),
                Float.random(in: spot.min.y...spot.max.y),
                Float.random(in: spot.min.z...spot.max.z)
            ) * 0.7 + spot.center * 0.3
            let origin = body.convert(position: local, to: mouthBubbles)
            let outward = origin - center
            let length = simd_length(outward)
            mouthBubbleSpheres.emit(
                count: 1,
                origin: origin,
                direction: length > 1e-4 ? outward / length : [0, 1, 0],
                radiusScale: Float.random(in: 0.1...1) < 0.8 ? Float.random(in: 0.12...0.3) : Float.random(in: 0.4...0.65),
                speedScale: Float.random(in: 0.12...0.35)
            )
        }
    }

    private func resetAudioBubbles() {
        audioBigBubbleBacklog = 0
        audioSmallBubbleBacklog = 0
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
