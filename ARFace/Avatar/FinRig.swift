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
    /// 0...1 per side (fish's left, right): the side fin swings up and folds over the eye, like a
    /// hand hiding it (a blush). Its usual motion fades out meanwhile.
    var cover = SIMD2<Float>(repeating: 0)
    /// 0...1: the fish is swimming under its own power (a lap). The tail beats hard, the side fins
    /// paddle and tuck back, the dorsal fin folds back.
    var propulsion: Float = 0
    /// The swim stroke's phase (radians), shared with the body wave so the bend runs into the tail.
    private(set) var strokePhase: Float = 0
    var finWave: Float = 1
    var finWaveSpeed: Float = 1

    private let logger = Logger(subsystem: "ARFace", category: "FinRig")
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
            for index in 0..<2 {
                let waveAngle = 5.6 * time + phase - 0.7 * Float(index)
                pose.pectoralFlap[sideIndex][index] = free * (flapSprings[sideIndex][index].angle
                    + 0.14 * finSway * energy * sin(waveAngle)
                    + (0.22 * propulsion + 0.4 * outside) * sin(0.5 * strokePhase + phase * 6 - 0.7 * Float(index)))   // paddling
                pose.pectoralSweep[sideIndex][index] = free * (sweepSprings[sideIndex][index].angle
                    - side * 0.08 * finSway * energy * sin(waveAngle + 1.2)
                    + side * 0.35 * propulsion   // tucked back while swimming
                    - side * 0.5 * inside)       // flared to brake on the inside of a turn
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
                    // Over the eye: a turn about the fin's root and a move up and forward, in the
                    // skeleton's space (+Y up, +Z forward, +X the fish's left; the right fin mirrors).
                    // Partway, the fin lifts out to the side first, so it never cuts through the face.
                    if root, pose.cover[side] > 0 {
                        let mirror: Float = side == 0 ? 1 : -1
                        let axis = simd_normalize(SIMD3<Float>(0.6813, -0.2077 * mirror, 0.7019 * mirror))
                        transform.rotation = simd_quatf(angle: 153.3 * .pi / 180 * pose.cover[side], axis: axis)
                            * transform.rotation
                        transform.translation += SIMD3<Float>(-0.02 * mirror, 0.2, 0.3) * pose.cover[side]
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
