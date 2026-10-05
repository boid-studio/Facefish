import Metal
import OSLog
import RealityKit
import UIKit

/// A small pooled field of lit sphere entities used instead of billboard particles.
final class BubbleSphereSystem {
    private struct Bubble {
        let entity: ModelEntity
        var velocity: SIMD3<Float> = .zero
        var age: Float = 0
        var life: Float = 0
        var radius: Float = 0
    }

    private let parent: Entity
    private let mesh: MeshResource
    private let material: any Material
    private var bubbles: [Bubble]
    private let lifeSpan: Float
    private let lifeVariation: Float
    private let speed: Float
    private let speedVariation: Float
    private let acceleration: SIMD3<Float>
    private let damping: Float
    private let spawnRadius: SIMD3<Float>
    private let radius: Float
    private var emissionRemainder: Float = 0

    init(
        parent: Entity,
        capacity: Int,
        radius: Float,
        color: UIColor,
        lifeSpan: Float,
        lifeVariation: Float,
        speed: Float,
        speedVariation: Float,
        acceleration: SIMD3<Float>,
        damping: Float,
        spawnRadius: SIMD3<Float>
    ) {
        self.parent = parent
        self.radius = radius
        self.mesh = .generateSphere(radius: 1)
        self.material = Self.bubbleMaterial(color: color)
        self.lifeSpan = lifeSpan
        self.lifeVariation = lifeVariation
        self.speed = speed
        self.speedVariation = speedVariation
        self.acceleration = acceleration
        self.damping = damping
        self.spawnRadius = spawnRadius
        self.bubbles = []
        self.bubbles.reserveCapacity(capacity)

        for _ in 0..<capacity {
            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.isEnabled = false
            parent.addChild(entity)
            bubbles.append(Bubble(entity: entity))
        }
    }

    private static func bubbleMaterial(color: UIColor) -> any Material {
        let tint = color.withAlphaComponent(1)
        if let library = MTLCreateSystemDefaultDevice()?.makeDefaultLibrary(),
           var material = try? CustomMaterial(
               from: UnlitMaterial(color: tint),
               surfaceShader: .init(named: "bubbleSurface", in: library)
           ) {
            material.blending = .transparent(opacity: .init(floatLiteral: 1))
            return material
        }
        var fallback = PhysicallyBasedMaterial()
        fallback.baseColor = .init(tint: tint)
        fallback.roughness = 0.05
        fallback.specular = .init(floatLiteral: 1)
        fallback.blending = .transparent(opacity: 0.15)
        return fallback
    }

    func emit(count: Int) {
        guard count > 0 else { return }
        for _ in 0..<count {
            guard let index = bubbles.firstIndex(where: { !$0.entity.isEnabled }) else { return }
            spawn(index: index)
        }
    }

    func update(deltaTime: TimeInterval, emissionRate: Float = 0, time: Float = 0) {
        guard deltaTime.isFinite, deltaTime > 0 else { return }
        let dt = Float(min(deltaTime, 0.1))

        if emissionRate > 0 {
            emissionRemainder += emissionRate * dt
            let count = Int(emissionRemainder)
            emissionRemainder -= Float(count)
            emit(count: count)
        }

        for index in bubbles.indices where bubbles[index].entity.isEnabled {
            bubbles[index].age += dt
            let bubble = bubbles[index]
            let remaining = bubble.life - bubble.age
            guard remaining > 0 else {
                bubbles[index].entity.isEnabled = false
                continue
            }

            bubbles[index].velocity += acceleration * dt
            bubbles[index].velocity *= max(0, 1 - damping * dt)
            let wobble = SIMD3<Float>(
                sin(time * 2.3 + Float(index)) * 0.002,
                0,
                cos(time * 1.7 + Float(index)) * 0.002
            )
            bubbles[index].entity.position += (bubbles[index].velocity + wobble) * dt

            let fadeIn = min(1, bubble.age / 0.12)
            let fadeOut = min(1, remaining / 0.5)
            let fade = min(fadeIn, fadeOut)
            bubbles[index].entity.scale = SIMD3(repeating: bubble.radius * fade)
        }
    }

    private func spawn(index: Int) {
        let direction = SIMD3<Float>(
            Float.random(in: -0.5...0.5),
            1,
            Float.random(in: 0.1...0.8)
        )
        let normalizedDirection = simd_normalize(direction)
        bubbles[index].age = 0
        bubbles[index].life = max(0.1, lifeSpan + Float.random(in: -lifeVariation...lifeVariation))
        bubbles[index].radius = radius * Float.random(in: 0.75...1.25)
        bubbles[index].velocity = normalizedDirection * (speed + Float.random(in: -speedVariation...speedVariation))
        bubbles[index].entity.position = SIMD3(
            Float.random(in: -spawnRadius.x...spawnRadius.x),
            Float.random(in: -spawnRadius.y...spawnRadius.y),
            Float.random(in: -spawnRadius.z...spawnRadius.z)
        )
        bubbles[index].entity.scale = .zero
        bubbles[index].entity.isEnabled = true
    }
}

/// Dresses the Reality Composer Pro `UnderwaterScene` anchors (Backdrop, BubbleEmitter)
/// with a sea-blue backdrop, light from above, caustics (see Underwater.metal) and rising bubbles.
final class UnderwaterSceneController {
    private let library = MTLCreateSystemDefaultDevice()?.makeDefaultLibrary()
    private let logger = Logger(subsystem: "ARFace", category: "Underwater")
    private var dapples: [(light: SpotLight, phase: Float)] = []
    private var time: Float = 0
    private var ambientBubbles: BubbleSphereSystem?

    init(scene: Entity) {
        if library == nil {
            logger.error("Metal library unavailable; caustic and fin-ripple shaders are disabled.")
        }
        addLights(to: scene)
        addBackdrop(to: scene.findEntity(named: "Backdrop") ?? scene)
        if let emitter = scene.findEntity(named: "BubbleEmitter") {
            ambientBubbles = BubbleSphereSystem(
                parent: emitter,
                capacity: 45,
                radius: 0.007,
                color: UIColor(red: 0.85, green: 0.97, blue: 1, alpha: 0.75),
                lifeSpan: 18,
                lifeVariation: 3,
                speed: 0.02,
                speedVariation: 0.008,
                acceleration: [0, 0.004, 0],
                damping: 0.05,
                spawnRadius: [0.45, 0.5, 0.2]
            )
            ambientBubbles?.emit(count: 10)
        }
    }

    /// Wanders the dappled spotlights so patches of light drift across the fish.
    func update(deltaTime: TimeInterval) {
        guard deltaTime.isFinite, deltaTime > 0 else { return }
        time += Float(min(deltaTime, 0.1))
        ambientBubbles?.update(deltaTime: deltaTime, emissionRate: 25, time: time)
        for (light, phase) in dapples {
            let t = time + phase
            light.position = [sin(t * 0.7) * 0.1 + sin(t * 1.9) * 0.03, 0.6, cos(t * 0.5) * 0.06 + 0.05]
            light.light.intensity = 9000 * (0.55 + 0.45 * sin(t * 2.3) * sin(t * 1.3 + 1))
        }
    }

    /// Gives single-part meshes (fins, eyes) the caustic shader. Multi-part USD meshes such as the
    /// subdivided, blend-shaped body don't render with CustomMaterial, so they rely on the dappled lights.
    func applyCaustics(to entity: Entity) {
        applyCaustics(to: entity, inheritedFin: nil)
    }

    private func applyCaustics(to entity: Entity, inheritedFin: FinWaveConfiguration?) {
        let fin = FinWaveConfiguration.matching(entity.name) ?? inheritedFin
        if let existingModel = entity.components[ModelComponent.self] {
            let partCount = existingModel.mesh.contents.models.map(\.parts.count).reduce(0, +)
            if partCount == 1 {
                var model = existingModel
                model.materials = model.materials.map { causticMaterial(from: $0, fog: 0, fin: fin) ?? $0 }
                entity.components.set(model)
            } else if fin != nil {
                logger.error("Fin mesh \(entity.name, privacy: .public) has multiple parts; fin ripple is unavailable.")
            }
        }
        for child in entity.children {
            applyCaustics(to: child, inheritedFin: fin)
        }
    }

    private func causticMaterial(from base: any Material, fog: Float, fin: FinWaveConfiguration?) -> CustomMaterial? {
        guard let library else { return nil }
        do {
            if let fin {
                var material = try CustomMaterial(
                    from: base,
                    surfaceShader: .init(named: "causticFinSurface", in: library),
                    geometryModifier: .init(named: fin.shaderName, in: library)
                )
                material.custom.value = [fin.amplitude, fin.wavelength, fin.falloff, 0]
                material.faceCulling = .none
                return material
            }

            var material = try CustomMaterial(from: base, surfaceShader: .init(named: "causticSurface", in: library))
            // Pattern frequency per metre, focus, strength, distance fog.
            material.custom.value = [32, 6, 1.4, fog]
            return material
        } catch {
            logger.error("Caustic material unavailable: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Lighting

    private func addLights(to scene: Entity) {
        let sun = DirectionalLight()
        sun.light.color = UIColor(red: 0.75, green: 0.93, blue: 1.0, alpha: 1)
        sun.light.intensity = 4000
        sun.shadow = DirectionalLightComponent.Shadow(maximumDistance: 2, depthBias: 1)
        sun.look(at: .zero, from: [0.1, 1, 0.25], relativeTo: nil)
        scene.addChild(sun)

        let fill = DirectionalLight()
        fill.light.color = UIColor(red: 0.2, green: 0.55, blue: 0.75, alpha: 1)
        fill.light.intensity = 1000
        fill.look(at: .zero, from: [-0.3, -0.2, 1], relativeTo: nil)
        scene.addChild(fill)

        for phase: Float in [0, 2.1, 4.3] {
            let spot = SpotLight()
            spot.light.color = UIColor(red: 0.8, green: 0.97, blue: 1.0, alpha: 1)
            spot.light.innerAngleInDegrees = 6
            spot.light.outerAngleInDegrees = 16
            spot.light.attenuationRadius = 2
            spot.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
            scene.addChild(spot)
            dapples.append((spot, phase))
        }
        update(deltaTime: 0.001)
    }

    // MARK: - Backdrop

    private func addBackdrop(to parent: Entity) {
        let material: any Material
        do {
            guard let library else { throw CocoaError(.featureUnsupported) }
            material = try CustomMaterial(surfaceShader: .init(named: "backdropSurface", in: library), lightingModel: .unlit)
        } catch {
            logger.error("Backdrop shader unavailable: \(error.localizedDescription)")
            material = UnlitMaterial(color: UIColor(red: 0.02, green: 0.26, blue: 0.44, alpha: 1))
        }
        parent.addChild(ModelEntity(mesh: .generatePlane(width: 6, height: 4), materials: [material]))
    }

}
