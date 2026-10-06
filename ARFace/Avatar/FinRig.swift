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
    }

    private enum JointMotion {
        case tail(Int)
        case pectoralFlap(side: Int, index: Int)
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
    var finWave: Float = 1
    var finWaveSpeed: Float = 1

    private let logger = Logger(subsystem: "ARFace", category: "FinRig")
    private var modelRigs: [ModelRig] = []
    private var waveTargets: [WaveTarget] = []
    private var boundJointNames: Set<String> = []
    private var tailSprings = [Spring](repeating: Spring(), count: 3)
    private var flapSprings = Array(repeating: [Spring](repeating: Spring(), count: 2), count: 2)
    private var sweepSprings = Array(repeating: [Spring](repeating: Spring(), count: 2), count: 2)
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
        turnRate += ((turn - (lastTurn ?? turn)) / deltaTime - turnRate) * rateAlpha
        nodRate += ((nod - (lastNod ?? nod)) / deltaTime - nodRate) * rateAlpha
        lastTurn = turn
        lastNod = nod

        let energy = 0.6 + 1.2 * min(1, max(0, mouthOpen))
        let steps = max(1, Int((deltaTime / (1.0 / 120)).rounded(.up)))
        let stepTime = deltaTime / Float(steps)

        let tailTarget = min(max(-turnRate * 0.35 * finReaction, -0.8), 0.8)
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
            for index in 0..<2 {
                let waveAngle = 5.6 * time + phase - 0.7 * Float(index)
                pose.pectoralFlap[sideIndex][index] = flapSprings[sideIndex][index].angle
                    + 0.14 * finSway * energy * sin(waveAngle)
                pose.pectoralSweep[sideIndex][index] = sweepSprings[sideIndex][index].angle
                    - side * 0.08 * finSway * energy * sin(waveAngle + 1.2)
            }
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
        if let configuration, let model = entity as? ModelEntity,
           entity.components[ModelComponent.self] != nil {
            waveTargets.append(WaveTarget(model: model, configuration: configuration))
            let restTransforms = model.jointTransforms
            let joints = zip(model.jointNames, restTransforms).enumerated().compactMap { index, pair -> JointBinding? in
                let name = pair.0.split(separator: "/").last.map(String.init) ?? pair.0
                let normalized = name.lowercased().filter { $0.isLetter || $0.isNumber }
                let motion: JointMotion?
                switch normalized {
                case "tail1": motion = .tail(0)
                case "tail2": motion = .tail(1)
                case "tail3": motion = .tail(2)
                case "pecl0", "pecl1": motion = .pectoralFlap(side: 0, index: 0)
                case "pecl2": motion = .pectoralFlap(side: 0, index: 1)
                case "pecr0", "pecr1": motion = .pectoralFlap(side: 1, index: 0)
                case "pecr2": motion = .pectoralFlap(side: 1, index: 1)
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
                case let .pectoralFlap(side, index):
                    transform.rotation = transform.rotation
                        * simd_quatf(angle: pose.pectoralFlap[side][index], axis: [1, 0, 0])
                        * simd_quatf(angle: pose.pectoralSweep[side][index], axis: [0, 0, 1])
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
