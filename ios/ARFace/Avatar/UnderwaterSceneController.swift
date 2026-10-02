import Metal
import OSLog
import RealityKit
import UIKit

/// Dresses the Reality Composer Pro `UnderwaterScene` anchors (Backdrop, BubbleEmitter)
/// with a sea-blue backdrop, light from above, caustics (see Underwater.metal) and rising bubbles.
final class UnderwaterSceneController {
    private let library = MTLCreateSystemDefaultDevice()?.makeDefaultLibrary()
    private let logger = Logger(subsystem: "ARFace", category: "Underwater")
    private var dapples: [(light: SpotLight, phase: Float)] = []
    private var time: Float = 0

    init(scene: Entity) {
        addLights(to: scene)
        addBackdrop(to: scene.findEntity(named: "Backdrop") ?? scene)
        scene.findEntity(named: "BubbleEmitter")?.components.set(Self.bubbles())
    }

    /// Wanders the dappled spotlights so patches of light drift across the fish.
    func update(deltaTime: TimeInterval) {
        guard deltaTime.isFinite, deltaTime > 0 else { return }
        time += Float(min(deltaTime, 0.1))
        for (light, phase) in dapples {
            let t = time + phase
            light.position = [sin(t * 0.7) * 0.1 + sin(t * 1.9) * 0.03, 0.6, cos(t * 0.5) * 0.06 + 0.05]
            light.light.intensity = 9000 * (0.55 + 0.45 * sin(t * 2.3) * sin(t * 1.3 + 1))
        }
    }

    /// Gives single-part meshes (fins, eyes) the caustic shader. Multi-part USD meshes such as the
    /// subdivided, blend-shaped body don't render with CustomMaterial, so they rely on the dappled lights.
    func applyCaustics(to entity: Entity) {
        if var model = entity.components[ModelComponent.self], model.mesh.contents.models.map(\.parts.count).reduce(0, +) == 1 {
            model.materials = model.materials.map { causticMaterial(from: $0, fog: 0) ?? $0 }
            entity.components.set(model)
        }
        for child in entity.children {
            applyCaustics(to: child)
        }
    }

    private func causticMaterial(from base: any Material, fog: Float) -> CustomMaterial? {
        guard let library else { return nil }
        do {
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

    // MARK: - Bubbles

    private static func bubbles() -> ParticleEmitterComponent {
        var component = ParticleEmitterComponent()
        component.emitterShape = .box
        component.birthLocation = .volume
        component.emitterShapeSize = [0.9, 0.02, 0.4]
        component.birthDirection = .local
        component.emissionDirection = [0, 1, 0]
        component.speed = 0.02
        component.speedVariation = 0.008

        var particles = component.mainEmitter
        particles.birthRate = 25
        particles.birthRateVariation = 10
        particles.lifeSpan = 18
        particles.lifeSpanVariation = 3
        particles.size = 0.007
        particles.sizeVariation = 0.005
        particles.acceleration = [0, 0.004, 0]
        particles.dampingFactor = 0.05
        particles.noiseStrength = 0.02
        particles.noiseScale = 0.1
        particles.noiseAnimationSpeed = 0.4
        particles.color = .constant(.single(UIColor(red: 0.85, green: 0.97, blue: 1, alpha: 0.75)))
        particles.opacityCurve = .gradualFadeInOut
        particles.blendMode = .additive
        component.mainEmitter = particles
        return component
    }
}
