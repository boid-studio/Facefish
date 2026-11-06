import Foundation
import OSLog
import RealityKit
import simd

struct FinWaveConfiguration {
    let shaderName: String
    let amplitude: Float
    let wavelength: Float
    let speed: Float
    let falloff: Float

    static let tail = FinWaveConfiguration(
        shaderName: "finWaveTail",
        amplitude: 0.151,
        wavelength: 4.04,
        speed: 0.8,
        falloff: 3.08
    )
    static let dorsal = FinWaveConfiguration(
        shaderName: "finWaveDorsal",
        amplitude: 0.1498,
        wavelength: 4.04,
        speed: 0.8,
        falloff: 3.08
    )
    static let pectoral = FinWaveConfiguration(
        shaderName: "finWavePectoral",
        amplitude: 0.1266,
        wavelength: 4.04,
        speed: 0.8,
        falloff: 3.08
    )

    static func matching(_ name: String) -> FinWaveConfiguration? {
        let normalized = name.lowercased().filter { $0.isLetter || $0.isNumber }
        if normalized.contains("tail") { return .tail }
        if normalized.contains("dorsal") { return .dorsal }
        if normalized.contains("pectoral") { return .pectoral }
        return nil
    }
}

/// Springs drive the fin bones while custom geometry modifiers ripple their UV-mapped surfaces.
final class FinRig {
    private struct Spring {
        var angle: Float = 0
        var velocity: Float = 0

        mutating func step(to target: Float, stiffness: Float, ratio: Float, deltaTime: Float) {
            velocity += (stiffness * (target - angle) - 2 * ratio * sqrt(stiffness) * velocity) * deltaTime
            angle += velocity * deltaTime
        }
    }

    private struct Pose {
        var tail = [Float](repeating: 0, count: 3)
        var pectoralFlap = Array(repeating: [Float](repeating: 0, count: 2), count: 2)
        var pectoralSweep = Array(repeating: [Float](repeating: 0, count: 2), count: 2)
        /// Dorsal (top) fin, root to tip: sideways bend (about each joint's local Z, + toward the
        /// fish's right) and fore-aft lean (about local X, + toward the front).
        var dorsalSide = [Float](repeating: 0, count: 3)
        var dorsalLean = [Float](repeating: 0, count: 3)
        /// Side fins over the eyes (fish's left, right), 0...1.
        var cover: [Float] = [0, 0]
    }

    private enum JointMotion {
        case tail(Int)
        case pectoralFlap(side: Int, index: Int, root: Bool)
        case dorsal(Int)
    }

    private struct JointBinding {
        let index: Int
        let rest: Transform
        let motion: JointMotion
    }

    private struct ModelRig {
        let model: ModelEntity
        let joints: [JointBinding]
    }

    private struct WaveTarget {
        let model: ModelEntity
        let configuration: FinWaveConfiguration
        var phase: Float = 0
    }

    var finReaction: Float = 1
    var finSway: Float = 1
    /// Extra turn of the whole fish (radians) on top of the head's, e.g. swimming a lap: the fins
    /// react to it like to a head turn.
    var bodyTurn: Float = 0
    /// Turn and nod speed of the whole fish (rad/s) on top of the head's, e.g. a spin or a loop.
    var bodyTurnRate: Float = 0
    var bodyNodRate: Float = 0
    /// -1...1, a turn the fish is about to make (+ toward its left): the fins steer before the
    /// body turns. The tail flexes toward it, the outside side fin paddles, the inside one brakes.
    var steer: Float = 0
    /// 0...1 per side (fish's left, right): the side fin takes up a gesture pose (`gesture`), by
    /// default over the eye, like a hand hiding it (a blush). Its usual motion fades out meanwhile.
    var cover = SIMD2<Float>(repeating: 0)
    /// The pose each side fin takes as `cover` goes to 1 (fish's left, right).
    var gesture: [FinPose] = [.cover, .cover]
    /// Extra room (model units) a side fin keeps from the face over its eye when covering it (fish's
    /// left, right): for something she wears there, such as a mask (Accessory.coverClearance).
    var coverClearance = SIMD2<Float>(repeating: 0)
    /// Out from the head's middle through the left eye, in the skeleton's space: the right fin's is
    /// mirrored like its moves.
    private static let coverOutward = simd_normalize(SIMD3<Float>(0.604, 0.290, 0.742))
    /// How hard the side fins paddle while swimming under their own power (1 = as on a lap).
    var paddleBoost: Float = 1
    /// -1...1: both side fins flap together (a laugh's "ha"s).
    var clap: Float = 0
    /// 0...1: the side fins open wide like arms and the dorsal fin stands up (singing a big note).
    var spread: Float = 0
    /// 0...1: the fish is swimming under its own power (a lap). The tail beats hard, the side fins
    /// paddle and tuck back, the dorsal fin folds back.
    var propulsion: Float = 0
    /// The swim stroke's phase (radians), shared with the body wave so the bend runs into the tail.
    private(set) var strokePhase: Float = 0
    var finWave: Float = 1
    var finWaveSpeed: Float = 1

    private let logger = Logger(subsystem: "ARFace", category: "FinRig")

    /// A rotation from a rotation vector (axis * radians).
    private static func turn(_ vector: SIMD3<Float>) -> simd_quatf {
        let angle = simd_length(vector)
        return angle > 1e-6 ? simd_quatf(angle: angle, axis: vector / angle) : simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    }
    private var modelRigs: [ModelRig] = []
    private var waveTargets: [WaveTarget] = []
    private var boundJointNames: Set<String> = []
    private var tailSprings = [Spring](repeating: Spring(), count: 3)
    private var flapSprings = Array(repeating: [Spring](repeating: Spring(), count: 2), count: 2)
    private var sweepSprings = Array(repeating: [Spring](repeating: Spring(), count: 2), count: 2)
    private var dorsalSideSprings = [Spring](repeating: Spring(), count: 3)
    private var dorsalLeanSprings = [Spring](repeating: Spring(), count: 3)
    private var lastTurn: Float?
    private var lastNod: Float?
    private var lastTrackedTurn: Float = 0
    private var lastTrackedNod: Float = 0
    private var turnRate: Float = 0
    private var nodRate: Float = 0
    private var trackingLostDuration: Float = 0
    private var time: Float = 0
    private var isEnabled = true

    init(model: Entity) {
        var rigs: [ModelRig] = []
        collectModels(in: model, inheritedConfiguration: nil, rigs: &rigs)
        modelRigs = rigs

        let expectedJoints = ["tail1", "tail2", "tail3"]
        var missingJoints = expectedJoints.filter { !boundJointNames.contains($0) }
        let hasLeftPectoral = boundJointNames.contains("pecl0") ||
            (boundJointNames.contains("pecl1") && boundJointNames.contains("pecl2"))
        let hasRightPectoral = boundJointNames.contains("pecr0") ||
            (boundJointNames.contains("pecr1") && boundJointNames.contains("pecr2"))
        if !hasLeftPectoral { missingJoints.append("pectoralLeft") }
        if !hasRightPectoral { missingJoints.append("pectoralRight") }
        if !missingJoints.isEmpty {
            logger.error("Fish fin rig is missing joints: \(missingJoints.joined(separator: ", "))")
        }

        let availableWaves = Set(waveTargets.map(\.configuration.shaderName))
        let missingWaves = ["finWaveTail", "finWaveDorsal", "finWavePectoral"].filter {
            !availableWaves.contains($0)
        }
        if !missingWaves.isEmpty {
            logger.error("Fish model is missing fin meshes for ripples: \(missingWaves.joined(separator: ", "))")
        }
    }

    func setEnabled(_ enabled: Bool, refreshMaterials: Bool = false) {
        guard enabled != isEnabled || refreshMaterials else { return }
        let changed = enabled != isEnabled
        isEnabled = enabled
        if changed, !enabled {
            apply(Pose())
        }
        updateWaveMaterials(amplitudeScale: enabled ? finWave : 0)
    }

    func update(turn trackedTurn: Float?, nod trackedNod: Float?, mouthOpen: Float, deltaTime rawDeltaTime: TimeInterval) {
        guard rawDeltaTime.isFinite, rawDeltaTime > 0 else { return }
        guard isEnabled else { return }
        let deltaTime = Float(min(rawDeltaTime, 0.1))
        time += deltaTime

        let turn: Float
        let nod: Float
        if let trackedTurn, let trackedNod {
            trackingLostDuration = 0
            lastTrackedTurn = trackedTurn
            lastTrackedNod = trackedNod
            turn = trackedTurn
            nod = trackedNod
        } else {
            trackingLostDuration += deltaTime
            let returnToIdle = min(max((trackingLostDuration - 1.5) / 0.5, 0), 1)
            let trackedFade = max(0, 1 - trackingLostDuration / 1.5)
            let idleTime = max(0, trackingLostDuration - 1.5)
            let idleTurn = 10 * .pi / 180 * sin(idleTime * 0.5)
            let idleNod = 4 * .pi / 180 * sin(idleTime * 0.8 + 2)
            turn = lastTrackedTurn * trackedFade * (1 - returnToIdle) + idleTurn * returnToIdle
            nod = lastTrackedNod * trackedFade * (1 - returnToIdle) + idleNod * returnToIdle
        }

        let rateAlpha = 1 - exp(-deltaTime * 18)
        let totalTurn = turn + bodyTurn
        turnRate += ((totalTurn - (lastTurn ?? totalTurn)) / deltaTime + bodyTurnRate - turnRate) * rateAlpha
        nodRate += ((nod - (lastNod ?? nod)) / deltaTime + bodyNodRate - nodRate) * rateAlpha
        lastTurn = totalTurn
        lastNod = nod
        strokePhase += deltaTime * 2 * .pi * (1.1 + 2.0 * propulsion)

        let energy = 0.6 + 1.2 * min(1, max(0, mouthOpen))
        let steps = max(1, Int((deltaTime / (1.0 / 120)).rounded(.up)))
        let stepTime = deltaTime / Float(steps)

        let tailTarget = min(max(-turnRate * 0.35 * finReaction + 0.45 * steer, -0.8), 0.8)
        for _ in 0..<steps {
            var target = tailTarget
            for index in tailSprings.indices {
                tailSprings[index].step(to: target, stiffness: 70, ratio: 0.32, deltaTime: stepTime)
                target = tailSprings[index].angle
            }
        }

        var pose = Pose()
        for index in tailSprings.indices {
            pose.tail[index] = tailSprings[index].angle
                + 0.1 * finSway * energy * sin(4.2 * time - 0.9 * Float(index))
                + 0.57 * propulsion * sin(strokePhase - 1.1 * Float(index) - 2.2)   // the swim stroke
        }

        let flapTarget = min(max(nodRate * 0.3 * finReaction, -0.6), 0.6)
        for sideIndex in 0..<2 {
            let side: Float = sideIndex == 0 ? 1 : -1
            let forward = min(max(side * turnRate * 0.3 * finReaction, -0.6), 0.6)
            let sweepTarget = -side * forward
            for _ in 0..<steps {
                var flap = flapTarget
                var sweep = sweepTarget
                for index in 0..<2 {
                    flapSprings[sideIndex][index].step(to: flap, stiffness: 55, ratio: 0.35, deltaTime: stepTime)
                    sweepSprings[sideIndex][index].step(to: sweep, stiffness: 55, ratio: 0.35, deltaTime: stepTime)
                    flap = flapSprings[sideIndex][index].angle
                    sweep = sweepSprings[sideIndex][index].angle
                }
            }

            let phase: Float = sideIndex == 0 ? 0 : 0.5
            pose.cover[sideIndex] = min(max(sideIndex == 0 ? cover.x : cover.y, 0), 1)
            let free = 1 - 0.85 * pose.cover[sideIndex]
            let outside = max(0, -side * steer), inside = max(0, side * steer)
            // Swimming, the fins mustn't fold into the body: each stroke reaches out and comes back
            // to the side (not past it), and they tuck back only so far (the angles add up over
            // the fin's three joints).
            let paddle = min(0.22 * propulsion * paddleBoost + 0.4 * outside, 0.35)
            let maxTuck = 0.6 - 0.4 * min(max(propulsion, 0), 1)
            for index in 0..<2 {
                let waveAngle = 5.6 * time + phase - 0.7 * Float(index)
                let stroke = 0.5 + 0.5 * sin(0.5 * strokePhase + phase * 6 - 0.7 * Float(index))
                pose.pectoralFlap[sideIndex][index] = free * (flapSprings[sideIndex][index].angle
                    + 0.45 * clap
                    + 0.35 * spread
                    + 0.14 * finSway * energy * sin(waveAngle)
                    + paddle * stroke)            // paddling
                let sweep = sweepSprings[sideIndex][index].angle
                    - side * 0.08 * finSway * energy * sin(waveAngle + 1.2)
                    + side * 0.15 * propulsion   // tucked back a little while swimming
                    - side * 0.5 * inside        // flared to brake on the inside of a turn
                    - side * 0.6 * spread        // opened wide
                pose.pectoralSweep[sideIndex][index] = free * side * min(side * sweep, maxTuck)
            }
        }

        // Dorsal fin: it lags behind turns (the tip trails to the outside of the turn: turning
        // toward the fish's left bends it right) and leans against nods; each joint follows the
        // one below it, so the bend travels up to the tip and wobbles out. A slow sway at rest.
        let dorsalSideTarget = min(max(turnRate * 0.25 * finReaction, -0.5), 0.5)
        let dorsalLeanTarget = min(max(-nodRate * 0.2 * finReaction, -0.35), 0.35)
        for _ in 0..<steps {
            var side = dorsalSideTarget
            var lean = dorsalLeanTarget
            for index in 0..<3 {
                dorsalSideSprings[index].step(to: side, stiffness: 60, ratio: 0.3, deltaTime: stepTime)
                dorsalLeanSprings[index].step(to: lean, stiffness: 60, ratio: 0.3, deltaTime: stepTime)
                side = dorsalSideSprings[index].angle
                lean = dorsalLeanSprings[index].angle
            }
        }
        for index in 0..<3 {
            pose.dorsalSide[index] = dorsalSideSprings[index].angle
                + 0.06 * finSway * energy * sin(3.2 * time - 0.8 * Float(index) + 0.5)
            pose.dorsalLean[index] = dorsalLeanSprings[index].angle - 0.25 * propulsion   // folded back
                + 0.2 * spread                                                                // standing up
        }

        apply(pose)
        updateWaves(mouthOpen: mouthOpen, deltaTime: deltaTime)
    }

    private func collectModels(
        in entity: Entity,
        inheritedConfiguration: FinWaveConfiguration?,
        rigs: inout [ModelRig]
    ) {
        let configuration = FinWaveConfiguration.matching(entity.name) ?? inheritedConfiguration
        if let model = entity as? ModelEntity,
           entity.components[ModelComponent.self] != nil {
            if let configuration {
                waveTargets.append(WaveTarget(model: model, configuration: configuration))
            }
            let restTransforms = model.jointTransforms
            let joints = zip(model.jointNames, restTransforms).enumerated().compactMap { index, pair -> JointBinding? in
                let name = pair.0.split(separator: "/").last.map(String.init) ?? pair.0
                let normalized = name.lowercased().filter { $0.isLetter || $0.isNumber }
                let motion: JointMotion?
                switch normalized {
                case "tail1": motion = .tail(0)
                case "tail2": motion = .tail(1)
                case "tail3": motion = .tail(2)
                case "pecl0", "pecl1": motion = .pectoralFlap(side: 0, index: 0, root: normalized == "pecl0")
                case "pecl2": motion = .pectoralFlap(side: 0, index: 1, root: false)
                case "pecr0", "pecr1": motion = .pectoralFlap(side: 1, index: 0, root: normalized == "pecr0")
                case "pecr2": motion = .pectoralFlap(side: 1, index: 1, root: false)
                case "dorsal1": motion = .dorsal(0)
                case "dorsal2": motion = .dorsal(1)
                case "dorsal3": motion = .dorsal(2)
                default: motion = nil
                }
                guard let motion else { return nil }
                boundJointNames.insert(normalized)
                return JointBinding(index: index, rest: pair.1, motion: motion)
            }
            if !joints.isEmpty {
                rigs.append(ModelRig(model: model, joints: joints))
            }
        }
        for child in entity.children {
            collectModels(in: child, inheritedConfiguration: configuration, rigs: &rigs)
        }
    }

    private func apply(_ pose: Pose) {
        for rig in modelRigs {
            var transforms = rig.model.jointTransforms
            for joint in rig.joints {
                var transform = joint.rest
                switch joint.motion {
                case let .tail(index):
                    transform.rotation = transform.rotation * simd_quatf(angle: pose.tail[index], axis: [1, 0, 0])
                case let .pectoralFlap(side, index, root):
                    transform.rotation = transform.rotation
                        * simd_quatf(angle: pose.pectoralFlap[side][index], axis: [1, 0, 0])
                        * simd_quatf(angle: pose.pectoralSweep[side][index], axis: [0, 0, 1])
                    // A gesture (FinPose, e.g. over the eye): the fin turns about its root (in the
                    // skeleton's space: +Y up, +Z forward, +X the fish's left), stretches, and bends
                    // at its middle and tip joints to lie along the face. On the way it comes up
                    // edge-on from below and opens over the eye, clear of the face all along.
                    let cover = pose.cover[side]
                    if cover > 0 {
                        // The right fin mirrors the left: turns (x, -y, -z), moves (-x, y, z).
                        let mirror = side == 0 ? SIMD3<Float>(1, 1, 1) : SIMD3<Float>(1, -1, -1)
                        if root {
                            let pose = gesture[side]
                            transform.rotation = Self.turn(pose.swing * mirror * sin(.pi * cover))
                                * Self.turn(pose.rootTurn * mirror * cover) * transform.rotation
                            transform.scale *= 1 + (pose.stretch - 1) * cover
                            // Off a mask over the eye.
                            let clearance = pose.clearsEye ? Self.coverOutward * coverClearance[side] : .zero
                            let moves = SIMD3<Float>(side == 0 ? 1 : -1, 1, 1)
                            transform.translation += ((pose.rootMove + clearance) * cover + pose.arc * sin(.pi * cover)) * moves
                        } else {
                            let bend = index == 0 ? gesture[side].middleBend : gesture[side].tipBend
                            transform.rotation = transform.rotation * Self.turn(bend * mirror * cover)
                        }
                    }
                case let .dorsal(index):
                    transform.rotation = transform.rotation
                        * simd_quatf(angle: pose.dorsalSide[index], axis: [0, 0, 1])
                        * simd_quatf(angle: pose.dorsalLean[index], axis: [1, 0, 0])
                }
                transforms[joint.index] = transform
            }
            rig.model.jointTransforms = transforms
        }
    }

    private func updateWaves(mouthOpen: Float, deltaTime: Float) {
        let speedMultiplier = 1 + 0.6 * min(1, max(0, mouthOpen))
        for index in waveTargets.indices {
            waveTargets[index].phase += waveTargets[index].configuration.speed * finWaveSpeed * speedMultiplier * deltaTime
        }
        updateWaveMaterials(amplitudeScale: finWave)
    }

    private func updateWaveMaterials(amplitudeScale: Float) {
        for target in waveTargets {
            guard var component = target.model.components[ModelComponent.self] else { continue }
            component.materials = component.materials.map { base in
                guard var material = base as? CustomMaterial else { return base }
                material.custom.value = [
                    target.configuration.amplitude * amplitudeScale,
                    target.configuration.wavelength,
                    target.configuration.falloff,
                    target.phase
                ]
                return material
            }
            target.model.components.set(component)
        }
    }
}


/// A side-fin gesture pose for the fish's left fin (the right one mirrors it), solved against the
/// head, eyes, lids, lashes, brows, teeth and mask in Blender so it lies close but never cuts in,
/// on the way there too (tools: the fin-pose solver). Turns are rotation vectors (axis * radians):
/// the root's in the skeleton's space (+Y up, +Z forward, +X the fish's left), the middle and tip
/// joints' in their own. Stretch scales the root joint (local Y runs along the fin, Z across the
/// fan: a small Z folds the fan into a narrow "finger"); the move is the root's. On the way, the
/// swing turns the root and the arc moves it out of the way (most halfway, none at either end).
nonisolated struct FinPose: Equatable {
    var rootTurn: SIMD3<Float>
    var rootMove: SIMD3<Float>
    var stretch: SIMD3<Float>
    var middleBend: SIMD3<Float>
    var tipBend: SIMD3<Float>
    var swing: SIMD3<Float>
    var arc = SIMD3<Float>(repeating: 0)
    /// Over an eye: kept off a mask there (FinRig.coverClearance).
    var clearsEye = false

    /// Blush: over the eye, lying along the face (the lids stay open meanwhile; LidRig.maxClosed).
    static let cover = FinPose(
        rootTurn: [1.6760, 0.2255, 2.2613], rootMove: [0.0684, 0.0164, 0.3618],
        stretch: [0.7007, 1.1829, 0.6985], middleBend: [-0.4178, 0.1392, -0.2766],
        tipBend: [-0.6634, -0.9847, -0.1170], swing: [2.0002, 0.0748, -1.0005], clearsEye: true)

    /// Shush: folded into a "finger", upright in front of pursed lips (pucker 0.7).
    static let shush = FinPose(
        rootTurn: [0.6784, -0.0321, 1.8887], rootMove: [-0.4639, -0.3279, 0.8956],
        stretch: [0.85, 1.15, 0.3], middleBend: [0.4659, 0.4136, -0.4267],
        tipBend: [-0.7615, 0.1492, -0.2174], swing: [0.0058, -0.1575, -0.3003],
        arc: [0.2741, -0.1206, 0.0722])

    /// My lips are sealed: folded, its tip drawn along the closed lips from the far mouth corner
    /// (start) across (middle) to the near one (end), like a zip.
    static let zipStart = FinPose(
        rootTurn: [1.4525, 2.3208, 1.8089], rootMove: [-0.2215, 0.0025, 0.5932],
        stretch: [0.85, 1.15, 0.3], middleBend: [-0.4995, 0.2422, -0.1061],
        tipBend: [0.2104, -0.0825, 0.1279], swing: [-0.9239, -0.0396, 1.0754],
        arc: [0.2332, -0.4597, 0.0275])
    static let zipMiddle = FinPose(
        rootTurn: [1.7966, 2.3745, 1.8167], rootMove: [0.0402, 0.0127, 0.5119],
        stretch: [0.85, 1.15, 0.3], middleBend: [-0.5177, 0.4431, -0.2032],
        tipBend: [0.1905, -0.0236, 0.0765], swing: [-0.9239, -0.0396, 1.0754],
        arc: [0.2332, -0.4597, 0.0275])
    static let zipEnd = FinPose(
        rootTurn: [1.7656, 2.5889, 1.8442], rootMove: [0.1636, 0.0742, 0.3617],
        stretch: [0.85, 1.15, 0.3], middleBend: [-0.5299, 0.5134, -0.2032],
        tipBend: [0.4617, 0.1487, 0.031], swing: [0, 0, 0])

    /// Along the zip, 0 (start) ... 1 (end).
    static func zip(_ u: Float) -> FinPose {
        let u = min(max(u, 0), 1)
        return u < 0.5 ? mix(zipStart, zipMiddle, u * 2) : mix(zipMiddle, zipEnd, u * 2 - 1)
    }

    static func mix(_ a: FinPose, _ b: FinPose, _ t: Float) -> FinPose {
        func m(_ x: SIMD3<Float>, _ y: SIMD3<Float>) -> SIMD3<Float> { x + (y - x) * t }
        return FinPose(rootTurn: m(a.rootTurn, b.rootTurn), rootMove: m(a.rootMove, b.rootMove),
                       stretch: m(a.stretch, b.stretch), middleBend: m(a.middleBend, b.middleBend),
                       tipBend: m(a.tipBend, b.tipBend), swing: m(a.swing, b.swing), arc: m(a.arc, b.arc),
                       clearsEye: t < 0.5 ? a.clearsEye : b.clearsEye)
    }
}
