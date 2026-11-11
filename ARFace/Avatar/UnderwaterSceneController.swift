import Metal
import OSLog
import RealityKit
import UIKit

/// A small pooled field of lit sphere entities used instead of billboard particles.
final class BubbleSphereSystem {
    static let risingAcceleration: SIMD3<Float> = [0, 0.21, 0]
    static let risingDamping: Float = 1.8
    static let risingTurbulence: Float = 0.035

    private struct Bubble {
        let entity: ModelEntity
        var velocity: SIMD3<Float> = .zero
        var age: Float = 0
        var life: Float = 0
        var radius: Float = 0
        var turbulencePhase: Float = 0
        var turbulenceRate: Float = 1
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
    private let directionalSpread: Float
    private let turbulence: Float
    private let shrinksAtEndOfLife: Bool
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
        spawnRadius: SIMD3<Float>,
        directionalSpread: Float = 0.12,
        turbulence: Float = 0,
        shrinksAtEndOfLife: Bool = true,
        screenSpaceGlass: Bool = false
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
        self.directionalSpread = directionalSpread
        self.turbulence = turbulence
        self.shrinksAtEndOfLife = shrinksAtEndOfLife
        self.bubbles = []
        self.bubbles.reserveCapacity(capacity)

        for _ in 0..<capacity {
            let entity = screenSpaceGlass ? ModelEntity() : ModelEntity(mesh: mesh, materials: [material])
            entity.isEnabled = false
            parent.addChild(entity)
            bubbles.append(Bubble(entity: entity))
        }
    }

    var glassSpheres: [SIMD4<Float>] {
        guard parent.isEnabledInHierarchy else { return [] }
        return bubbles.compactMap { bubble in
            guard bubble.entity.isEnabled else { return nil }
            let transform = bubble.entity.transformMatrix(relativeTo: nil)
            let axis = transform.columns.0
            let radius = simd_length(SIMD3(axis.x, axis.y, axis.z))
            guard radius > 0 else { return nil }
            let position = bubble.entity.position(relativeTo: nil)
            return SIMD4(position, radius)
        }
    }

    private static func bubbleMaterial(color: UIColor) -> any Material {
        let logger = Logger(subsystem: "ARFace", category: "Bubbles")
        let tint = color.withAlphaComponent(1)
        do {
            guard let library = MTLCreateSystemDefaultDevice()?.makeDefaultLibrary() else {
                throw CocoaError(.featureUnsupported)
            }
            var material = try CustomMaterial(
                surfaceShader: .init(named: "bubbleSurface", in: library),
                lightingModel: .unlit
            )
            material.baseColor = .init(PhysicallyBasedMaterial.BaseColor(tint: tint))
            material.blending = .transparent(opacity: .init(floatLiteral: 1))
            return material
        } catch {
            logger.error("Bubble shader unavailable; using non-refractive fallback: \(error.localizedDescription)")
        }
        var fallback = PhysicallyBasedMaterial()
        fallback.baseColor = .init(tint: tint)
        fallback.roughness = 0.05
        fallback.specular = .init(floatLiteral: 1)
        fallback.blending = .transparent(opacity: 0.15)
        return fallback
    }

    func emit(
        count: Int,
        origin: SIMD3<Float> = .zero,
        direction: SIMD3<Float>? = nil,
        radiusScale: Float = 1,
        speedScale: Float = 1
    ) {
        guard count > 0 else { return }
        for _ in 0..<count {
            guard let index = bubbles.firstIndex(where: { !$0.entity.isEnabled }) else { return }
            spawn(index: index, origin: origin, direction: direction, radiusScale: radiusScale, speedScale: speedScale)
        }
    }

    func setEnabled(_ enabled: Bool) {
        parent.isEnabled = enabled
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
            let phase = bubble.turbulencePhase
            let driftTime = bubble.age * bubble.turbulenceRate
            let drift = SIMD3<Float>(
                sin(driftTime * 5.3 + phase),
                sin(driftTime * 3.7 + phase) * 0.3,
                cos(driftTime * 4.7 + phase)
            ) * turbulence
            bubbles[index].entity.position += (bubbles[index].velocity + wobble + drift) * dt

            let fadeIn = min(1, bubble.age / 0.12)
            let fadeOut: Float = shrinksAtEndOfLife ? min(1, remaining / 0.5) : 1
            let fade = min(fadeIn, fadeOut)
            bubbles[index].entity.scale = SIMD3(repeating: bubble.radius * fade)
        }
    }

    private func spawn(
        index: Int,
        origin: SIMD3<Float>,
        direction: SIMD3<Float>?,
        radiusScale: Float,
        speedScale: Float
    ) {
        let launchDirection = direction.map {
            $0 + SIMD3<Float>(
                Float.random(in: -directionalSpread...directionalSpread),
                Float.random(in: -directionalSpread...directionalSpread),
                Float.random(in: -directionalSpread...directionalSpread)
            )
        } ?? SIMD3<Float>(
            Float.random(in: -0.5...0.5),
            1,
            Float.random(in: 0.1...0.8)
        )
        let normalizedDirection = simd_normalize(launchDirection)
        bubbles[index].age = 0
        bubbles[index].life = max(0.1, lifeSpan + Float.random(in: -lifeVariation...lifeVariation))
        bubbles[index].radius = radius * radiusScale * Float.random(in: 0.75...1.25)
        bubbles[index].velocity = normalizedDirection * (speed + Float.random(in: -speedVariation...speedVariation)) * speedScale
        bubbles[index].turbulencePhase = Float.random(in: 0...(2 * .pi))
        bubbles[index].turbulenceRate = Float.random(in: 0.75...1.3)
        bubbles[index].entity.position = origin + SIMD3(
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
    private enum CausticKind {
        case face, surface
    }

    private struct MaterialOverride {
        let entity: Entity
        var enabledMaterials: [any Material]
        let disabledMaterials: [any Material]
        var kind: CausticKind?
    }

    private let library = MTLCreateSystemDefaultDevice()?.makeDefaultLibrary()
    private let logger = Logger(subsystem: "ARFace", category: "Underwater")
    private var dapples: [(light: SpotLight, phase: Float)] = []
    private var sun: DirectionalLight?
    private var fill: DirectionalLight?
    private var debris: [DebrisLayer] = []
    private var wake: Entity?
    private var debrisAmount: Float = 1
    private var waterMotion: Float = 1
    private var sloshOffset = SIMD3<Float>(repeating: 0)
    private var sloshVelocity = SIMD3<Float>(repeating: 0)
    /// The phone's movement without gravity (g, screen axes), to slosh the debris.
    var phoneAcceleration = SIMD3<Float>(repeating: 0)
    /// The camera's distance (the zoom), for the near debris in front of it.
    var cameraZ: Float = 0.75
    /// The phone is hot (thermal state serious or worse): half the debris and no wake, to cool it.
    var easesOff = false
    /// The water's colours for the shaders (WaterPalette in Underwater.metal), shared by every
    /// scene material: a new look rewrites it, not the materials.
    private var paletteTexture: TextureResource?
    private var look = SceneLook()
    private static let sunColor = SIMD3<Float>(0.75, 0.93, 1.0)
    private static let fillColor = SIMD3<Float>(0.2, 0.55, 0.75)
    private static let spotColor = SIMD3<Float>(0.8, 0.97, 1.0)
    private static let speckColor = SIMD3<Float>(0.88, 0.97, 1.0)
    private var materialOverrides: [MaterialOverride] = []
    private var time: Float = 0
    private var ambientBubbles: BubbleSphereSystem?
    private var causticsEnabled = true
    private var causticScale: Float = 1
    private var causticSpeed: Float = 1
    private var causticIntensity: Float = 1
    private var causticAngle: Float = 0
    private var ambientBubblesEnabled = true
    private var spotlightsEnabled = true
    private var shadowsEnabled = true

    var glassSpheres: [SIMD4<Float>] { ambientBubbles?.glassSpheres ?? [] }

    init(scene: Entity, screenSpaceGlass: Bool = false) {
        if library == nil {
            logger.error("Metal library unavailable; caustic and fin-ripple shaders are disabled.")
        }
        if let image = Self.paletteImage(look) {
            do {
                paletteTexture = try TextureResource(image: image, options: Self.paletteOptions)
            } catch {
                logger.error("Water palette unavailable; the sea stays blue: \(error.localizedDescription)")
            }
        }
        addLights(to: scene)
        addBackdrop(to: scene.findEntity(named: "Backdrop") ?? scene)
        addDebris(to: scene)
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
                acceleration: BubbleSphereSystem.risingAcceleration,
                damping: BubbleSphereSystem.risingDamping,
                spawnRadius: [0.45, 0.5, 0.2],
                turbulence: BubbleSphereSystem.risingTurbulence,
                screenSpaceGlass: screenSpaceGlass
            )
            ambientBubbles?.emit(count: 10)
        }
    }

    /// Wanders the dappled spotlights so patches of light drift across the fish.
    func update(deltaTime: TimeInterval, options: AvatarRenderOptions) {
        guard deltaTime.isFinite, deltaTime > 0 else { return }
        setCausticsEnabled(options.causticsEnabled)
        setCausticTuning(scale: options.causticScale, speed: options.causticSpeed, intensity: options.causticIntensity, angle: options.causticAngle)
        setAmbientBubblesEnabled(options.ambientBubblesEnabled)
        setSpotlightsEnabled(options.spotlightsEnabled)
        setShadowsEnabled(options.shadowsEnabled)
        setLook(options.look)
        setDebrisAmount(options.debrisAmount * (easesOff ? 0.5 : 1))
        waterMotion = options.waterMotion

        time += Float(min(deltaTime, 0.1))
        updateDebris(deltaTime: Float(min(deltaTime, 0.1)))
        if ambientBubblesEnabled {
            ambientBubbles?.update(deltaTime: deltaTime, emissionRate: 25, time: time)
        }
        if spotlightsEnabled {
            updateDapples()
        }
    }

    private func updateDapples() {
        for (light, phase) in dapples {
            let t = time + phase
            light.position = [sin(t * 0.7) * 0.13 + sin(t * 1.9) * 0.04, 0.6, cos(t * 0.5) * 0.08 + 0.05]
            light.light.intensity = 18_000 * (0.55 + 0.45 * sin(t * 2.3) * sin(t * 1.3 + 1))
        }
    }

    /// Gives single-part meshes (fins, eyes) the caustic shader. Multi-part USD meshes such as the
    /// subdivided, blend-shaped body don't render with CustomMaterial, so they rely on the dappled lights.
    func applyCaustics(to entity: Entity) {
        applyCaustics(to: entity, inheritedFin: nil, inheritedEyelid: false, inheritedAccessory: false)
    }

    private func applyCaustics(
        to entity: Entity,
        inheritedFin: FinWaveConfiguration?,
        inheritedEyelid: Bool,
        inheritedAccessory: Bool
    ) {
        let fin = FinWaveConfiguration.matching(entity.name) ?? inheritedFin
        let isEyelid = inheritedEyelid || entity.name.localizedCaseInsensitiveContains("eyelid")
        // The eyeballs: clean, glossy, without the caustics' glints or the water's tint.
        let isEyeball = !isEyelid && sequence(first: entity, next: \.parent).contains { ancestor in
            let name = ancestor.name.lowercased().filter(\.isLetter)
            return name == "eyel" || name == "eyer"
        }
        let isAccessory = inheritedAccessory || Accessory.part(named: entity.name) != nil
        if let existingModel = entity.components[ModelComponent.self] {
            let partCount = existingModel.mesh.contents.models.map(\.parts.count).reduce(0, +)
            let blendShapeMapping = BlendShapeWeightsMapping(meshResource: existingModel.mesh)
            let hasBlendShapes = !BlendShapeWeightsComponent(weightsMapping: blendShapeMapping).weightSet.isEmpty
            if entity.name == "Head" || isAccessory,
               let faceMaterials = faceCausticMaterials(for: existingModel.materials, accessory: isAccessory) {
                // The body, and what she wears on it: strong caustics on the face, bending as she swims.
                var model = existingModel
                model.materials = faceMaterials.enabled
                entity.components.set(model)
                materialOverrides.append(MaterialOverride(
                    entity: entity,
                    enabledMaterials: faceMaterials.enabled,
                    disabledMaterials: faceMaterials.disabled,
                    kind: .face
                ))
            } else if partCount == 1, !hasBlendShapes {
                var model = existingModel
                let originalMaterials = model.materials
                let enabledMaterials = isEyelid ? originalMaterials : originalMaterials.map {
                    (isEyeball ? eyeMaterial(from: $0) : customMaterial(from: $0, causticsEnabled: true, fog: 0, fin: fin)) ?? $0
                }
                let disabledMaterials = isEyelid ? originalMaterials : isEyeball ? enabledMaterials : originalMaterials.map {
                    customMaterial(from: $0, causticsEnabled: false, fog: 0, fin: fin) ?? $0
                }
                model.materials = enabledMaterials
                entity.components.set(model)
                materialOverrides.append(MaterialOverride(
                    entity: entity,
                    enabledMaterials: enabledMaterials,
                    disabledMaterials: disabledMaterials,
                    kind: fin == nil && !isEyelid && !isEyeball ? .surface : nil
                ))
            } else if fin != nil {
                logger.error("Fin mesh \(entity.name, privacy: .public) has multiple parts; fin ripple is unavailable.")
            }
        }
        for child in entity.children {
            applyCaustics(to: child, inheritedFin: fin, inheritedEyelid: isEyelid, inheritedAccessory: isAccessory)
        }
    }

    /// Face caustic materials for the body, or an accessory worn on it, which keeps its own
    /// finish (with and without caustics).
    private func faceCausticMaterials(for materials: [any Material], accessory: Bool = false) -> (enabled: [any Material], disabled: [any Material])? {
        guard let library else { return nil }
        func make(strength: Float) -> [any Material]? {
            var result: [any Material] = []
            for base in materials {
                guard var material = try? CustomMaterial(
                    from: base,
                    surfaceShader: .init(named: accessory ? "accessorySurface" : "faceCausticSurface", in: library),
                    geometryModifier: .init(named: "faceBodyBend", in: library)
                ) else { return nil }
                material.custom.value = [0, 0, strength, 0]   // swim bend amplitude, phase, caustic tuning (0 = off), blush
                withPalette(&material)
                result.append(material)
            }
            return result
        }
        guard let enabled = make(strength: Self.packedFaceTuning(scale: causticScale, speed: causticSpeed, intensity: causticIntensity, angle: causticAngle)),
              let disabled = make(strength: 0) else {
            logger.error("Face caustic material unavailable; the body keeps its own material.")
            return nil
        }
        return (enabled, disabled)
    }

    /// The eyeballs' material (eyeSurface): clean and glossy.
    private func eyeMaterial(from base: any Material) -> CustomMaterial? {
        guard let library else { return nil }
        guard var material = try? CustomMaterial(from: base, surfaceShader: .init(named: "eyeSurface", in: library)) else {
            return nil
        }
        material.custom.value = .zero
        return material
    }

    private func customMaterial(
        from base: any Material,
        causticsEnabled: Bool,
        fog: Float,
        fin: FinWaveConfiguration?
    ) -> CustomMaterial? {
        guard let library else { return nil }
        do {
            if let fin {
                var material = try CustomMaterial(
                    from: base,
                    surfaceShader: .init(
                        named: causticsEnabled ? "causticFinSurface" : "baseSurface",
                        in: library
                    ),
                    geometryModifier: .init(named: fin.shaderName, in: library)
                )
                material.custom.value = [fin.amplitude, fin.wavelength, fin.falloff, 0]
                material.faceCulling = .none
                withPalette(&material)
                return material
            }

            let shaderName = causticsEnabled ? "causticSurface" : "baseSurface"
            var material = try CustomMaterial(from: base, surfaceShader: .init(named: shaderName, in: library))
            // Pattern frequency per metre, focus, strength, animation speed.
            material.custom.value = [32 / causticScale, 6, 1.4 * causticIntensity, causticSpeed]
            withPalette(&material)
            return material
        } catch {
            logger.error("Caustic material unavailable: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Marine snow

    /// Faint specks drifting slowly through the water (marine snow), always there.
    /// One depth layer of debris drifting in the water.
    private struct DebrisLayer {
        let entity: Entity
        /// Where it sits; near layers ride along in front of the camera.
        let base: SIMD3<Float>
        let followsCamera: Bool
        /// How much the current and the phone's sloshing move it (nearer moves more: parallax).
        let parallax: Float
        let birthRate: Float
        let alpha: CGFloat
        let brightness: Float
    }

    /// Marine snow and debris in three depths (far, mid, near) and a few glints, swirling in
    /// turbulence and swaying together in a slow, wandering current; the phone's movement sloshes
    /// them, nearer ones more. `debrisAmount` and `waterMotion` (the Scene tab) scale it all.
    private func addDebris(to scene: Entity) {
        func layer(
            at base: SIMD3<Float>, followsCamera: Bool = false, box: SIMD3<Float>, parallax: Float,
            birthRate: Float, lifeSpan: Double, size: Float, sizeVariation: Float, alpha: CGFloat,
            brightness: Float = 1, noise: Float, noiseScale: Float, noiseSpeed: Float, sink: Float,
            opacity: ParticleEmitterComponent.ParticleEmitter.OpacityCurve = .gradualFadeInOut,
            additive: Bool = false
        ) {
            var particles = ParticleEmitterComponent()
            particles.emitterShape = .box
            particles.birthLocation = .volume
            particles.emitterShapeSize = box
            particles.emissionDirection = [0, -1, 0]
            particles.speed = sink
            particles.speedVariation = sink * 0.8
            particles.particlesInheritTransform = true   // they sway with the current
            var specks = particles.mainEmitter
            specks.birthRate = birthRate
            specks.lifeSpan = lifeSpan
            specks.lifeSpanVariation = lifeSpan * 0.35
            specks.size = size
            specks.sizeVariation = sizeVariation
            specks.spreadingAngle = .pi / 2
            specks.blendMode = additive ? .additive : .alpha
            specks.isLightingEnabled = false
            specks.opacityCurve = opacity
            specks.noiseStrength = noise          // turbulence: eddies that push them about
            specks.noiseScale = noiseScale
            specks.noiseAnimationSpeed = noiseSpeed
            specks.dampingFactor = 0.6
            specks.color = .constant(.single(Self.uiColor(Self.speckColor * brightness, alpha: alpha)))
            particles.mainEmitter = specks
            // Start full rather than empty.
            particles.burstCount = Int(birthRate * Float(lifeSpan) * 0.6)
            particles.burst()
            let entity = Entity()
            entity.position = base
            entity.components.set(particles)
            scene.addChild(entity)
            debris.append(DebrisLayer(entity: entity, base: base, followsCamera: followsCamera,
                                      parallax: parallax, birthRate: birthRate, alpha: alpha,
                                      brightness: brightness))
        }
        // Far: many tiny, dim specks between the fish and the backdrop.
        layer(at: [0, 0, -0.9], box: [2.2, 1.6, 0.8], parallax: 0.4, birthRate: 140, lifeSpan: 9,
              size: 0.0048, sizeVariation: 0.002, alpha: 0.38, brightness: 0.85,
              noise: 0.012, noiseScale: 1.4, noiseSpeed: 0.18, sink: 0.004)
        // Mid: around the fish, the main snow.
        layer(at: [0, 0, -0.15], box: [1.3, 1.1, 0.8], parallax: 1, birthRate: 100, lifeSpan: 8,
              size: 0.0065, sizeVariation: 0.0035, alpha: 0.5,
              noise: 0.022, noiseScale: 2.6, noiseSpeed: 0.32, sink: 0.005)
        // Near: a few big, soft flakes drifting past close to the lens, out of focus.
        layer(at: [0, 0, 0.4], followsCamera: true, box: [0.55, 0.7, 0.3], parallax: 1.8, birthRate: 7,
              lifeSpan: 7, size: 0.022, sizeVariation: 0.01, alpha: 0.16,
              noise: 0.03, noiseScale: 1.8, noiseSpeed: 0.25, sink: 0.006)
        // Glints: now and then a speck catches the light, briefly.
        layer(at: [0, 0.1, -0.2], box: [1.2, 0.9, 0.7], parallax: 1, birthRate: 10, lifeSpan: 1.6,
              size: 0.0045, sizeVariation: 0.002, alpha: 0.55, brightness: 1.3,
              noise: 0.02, noiseScale: 2.6, noiseSpeed: 0.32, sink: 0.003,
              opacity: .quickFadeInOut, additive: true)

        // The wake: specks stirred up behind her when she swims fast (stir(at:speed:)).
        var wake = ParticleEmitterComponent()
        wake.emitterShape = .sphere
        wake.birthLocation = .volume
        wake.emitterShapeSize = [0.05, 0.05, 0.05]
        wake.speed = 0.03
        wake.speedVariation = 0.02
        wake.particlesInheritTransform = false   // left behind
        wake.isEmitting = false
        var stirred = wake.mainEmitter
        stirred.birthRate = 60
        stirred.lifeSpan = 2.5
        stirred.lifeSpanVariation = 0.8
        stirred.size = 0.006
        stirred.sizeVariation = 0.003
        stirred.spreadingAngle = .pi
        stirred.blendMode = .alpha
        stirred.isLightingEnabled = false
        stirred.opacityCurve = .gradualFadeInOut
        stirred.noiseStrength = 0.08
        stirred.noiseScale = 4
        stirred.noiseAnimationSpeed = 0.6
        stirred.dampingFactor = 1.5
        stirred.color = .constant(.single(Self.uiColor(Self.speckColor, alpha: 0.45)))
        wake.mainEmitter = stirred
        let wakeEntity = Entity()
        wakeEntity.components.set(wake)
        scene.addChild(wakeEntity)
        self.wake = wakeEntity
    }

    /// Sways the debris in the current and the phone's sloshing; the near layer rides in front of
    /// the camera.
    private func updateDebris(deltaTime: Float) {
        let motion = min(max(waterMotion, 0), 2)
        // A slow current that wanders, now and then surging.
        let surge = pow(0.5 + 0.5 * sin(time * 0.13 + 1.1), 2)
        let current = SIMD3<Float>(
            0.03 * sin(time * 0.21) + 0.012 * sin(time * 0.57 + 2),
            0.012 * sin(time * 0.17 + 1.3) + 0.006 * sin(time * 0.71),
            0.015 * sin(time * 0.13 + 0.4)
        ) * (0.6 + 0.8 * surge) * motion
        // The phone moving: the water lags behind it and sloshes back.
        var push = -phoneAcceleration
        let strength = simd_length(push)
        if strength > 0.6 { push *= 0.6 / strength }
        let stiffness: Float = 6, ratio: Float = 0.25
        let steps = max(1, Int((deltaTime / (1.0 / 120)).rounded(.up)))
        let stepTime = deltaTime / Float(steps)
        for _ in 0..<steps {
            let spring = -stiffness * sloshOffset - 2 * ratio * sqrt(stiffness) * sloshVelocity
            sloshVelocity += (spring + push * 9.81 * 0.06 * motion) * stepTime
            sloshOffset += sloshVelocity * stepTime
        }
        if simd_length(sloshOffset) > 0.06 { sloshOffset *= 0.06 / simd_length(sloshOffset) }
        for layer in debris {
            var base = layer.base
            if layer.followsCamera { base.z = cameraZ - 0.35 }
            layer.entity.position = base + (current + sloshOffset) * layer.parallax
        }
    }

    /// Specks stirred up in the fish's wake: `position` where she is, `speed` how fast (m/s).
    func stir(at position: SIMD3<Float>, speed: Float) {
        guard let wake, var particles = wake.components[ParticleEmitterComponent.self] else { return }
        wake.position = position
        let amount = easesOff ? 0 : min(max(debrisAmount, 0), 2)
        // In steps, so the emitter isn't reset every frame.
        let level: Float = speed > 0.5 ? 3 : speed > 0.25 ? 2 : speed > 0.12 ? 1 : 0
        let emitting = level > 0 && amount > 0
        let rate = 40 * level * amount
        guard emitting != particles.isEmitting || (emitting && abs(rate - particles.mainEmitter.birthRate) > 1) else { return }
        particles.isEmitting = emitting
        if emitting { particles.mainEmitter.birthRate = rate }
        wake.components.set(particles)
    }

    private func setDebrisAmount(_ amount: Float) {
        guard amount != debrisAmount else { return }
        debrisAmount = amount
        for layer in debris {
            guard var particles = layer.entity.components[ParticleEmitterComponent.self] else { continue }
            particles.mainEmitter.birthRate = layer.birthRate * min(max(amount, 0), 2)
            layer.entity.components.set(particles)
        }
    }

    // MARK: - Lighting

    private func addLights(to scene: Entity) {
        let sun = DirectionalLight()
        sun.light.color = Self.uiColor(Self.sunColor)
        sun.light.intensity = 4000
        sun.shadow = DirectionalLightComponent.Shadow(maximumDistance: 2, depthBias: 1)
        sun.look(at: .zero, from: [0.1, 1, 0.25], relativeTo: nil)
        scene.addChild(sun)
        self.sun = sun

        let fill = DirectionalLight()
        fill.light.color = Self.uiColor(Self.fillColor)
        fill.light.intensity = 1000
        fill.look(at: .zero, from: [-0.3, -0.2, 1], relativeTo: nil)
        scene.addChild(fill)
        self.fill = fill

        for phase: Float in [0, 2.1, 4.3] {
            let spot = SpotLight()
            spot.light.color = Self.uiColor(Self.spotColor)
            spot.light.innerAngleInDegrees = 4
            spot.light.outerAngleInDegrees = 11
            spot.light.attenuationRadius = 2
            spot.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
            scene.addChild(spot)
            dapples.append((spot, phase))
        }
        time = 0.001
        updateDapples()
    }

    // MARK: - Backdrop

    private func addBackdrop(to parent: Entity) {
        let fallback = UnlitMaterial(color: UIColor(red: 0.02, green: 0.26, blue: 0.44, alpha: 1))
        let materials: (enabled: any Material, disabled: any Material)
        do {
            guard let library else { throw CocoaError(.featureUnsupported) }
            var enabled = try CustomMaterial(surfaceShader: .init(named: "backdropSurface", in: library), lightingModel: .unlit)
            var disabled = try CustomMaterial(
                surfaceShader: .init(named: "backdropBaseSurface", in: library),
                lightingModel: .unlit
            )
            withPalette(&enabled)
            withPalette(&disabled)
            materials = (enabled, disabled)
        } catch {
            logger.error("Backdrop shader unavailable: \(error.localizedDescription)")
            materials = (fallback, fallback)
        }
        let backdrop = ModelEntity(mesh: .generatePlane(width: 6, height: 4), materials: [materials.enabled])
        parent.addChild(backdrop)
        materialOverrides.append(MaterialOverride(
            entity: backdrop,
            enabledMaterials: [materials.enabled],
            disabledMaterials: [materials.disabled]
        ))
    }

    /// Face shader packs frequency, speed, intensity (steps of 0.05) and angle (steps of 5 degrees) into one
    /// float, mixed radix: ((f * 81 + s) * 61 + i) * 25 + a. Stays under 2^24 so it is exact.
    private static func packedFaceTuning(scale: Float, speed: Float, intensity: Float, angle: Float) -> Float {
        let f = min(max((20 / scale).rounded(), 0), 80)
        let s = min(max((speed * 20).rounded(), 0), 80)
        let i = min(max((intensity * 20).rounded(), 0), 60)
        let a = min(max((angle / 5).rounded(), -12), 12) + 12
        return ((f * 81 + s) * 61 + i) * 25 + a
    }

    private func setCausticTuning(scale: Float, speed: Float, intensity: Float, angle: Float) {
        guard scale != causticScale || speed != causticSpeed || intensity != causticIntensity
                || angle != causticAngle else { return }
        causticScale = scale
        causticSpeed = speed
        causticIntensity = intensity
        causticAngle = angle
        let packed = Self.packedFaceTuning(scale: scale, speed: speed, intensity: intensity, angle: angle)
        func tuned(_ materials: [any Material], kind: CausticKind) -> [any Material] {
            materials.map { base in
                guard var material = base as? CustomMaterial else { return base }
                switch kind {
                case .face: material.custom.value.z = packed
                case .surface:
                    material.custom.value.x = 32 / scale
                    material.custom.value.z = 1.4 * intensity
                    material.custom.value.w = speed
                }
                return material
            }
        }
        for index in materialOverrides.indices {
            guard let kind = materialOverrides[index].kind else { continue }
            materialOverrides[index].enabledMaterials = tuned(materialOverrides[index].enabledMaterials, kind: kind)
            guard causticsEnabled,
                  var model = materialOverrides[index].entity.components[ModelComponent.self] else { continue }
            model.materials = tuned(model.materials, kind: kind)
            materialOverrides[index].entity.components.set(model)
        }
    }

    private func setCausticsEnabled(_ enabled: Bool) {
        guard enabled != causticsEnabled else { return }
        causticsEnabled = enabled
        for override in materialOverrides {
            guard var model = override.entity.components[ModelComponent.self] else { continue }
            model.materials = enabled ? override.enabledMaterials : override.disabledMaterials
            override.entity.components.set(model)
        }
    }

    private func setAmbientBubblesEnabled(_ enabled: Bool) {
        guard enabled != ambientBubblesEnabled else { return }
        ambientBubblesEnabled = enabled
        ambientBubbles?.setEnabled(enabled)
    }

    private func setSpotlightsEnabled(_ enabled: Bool) {
        guard enabled != spotlightsEnabled else { return }
        spotlightsEnabled = enabled
        for (light, _) in dapples {
            light.isEnabled = enabled
        }
    }

    // MARK: - Look

    /// The water's colour: the palette texture every scene material reads, and the lights and specks.
    private func setLook(_ newLook: SceneLook) {
        guard newLook.water != look.water || newLook.brightness != look.brightness
                || newLook.underwaterTint != look.underwaterTint else { return }
        look = newLook
        if let paletteTexture, let image = Self.paletteImage(look) {
            do {
                try paletteTexture.replace(withImage: image, options: Self.paletteOptions)
            } catch {
                logger.error("Could not recolour the water: \(error.localizedDescription)")
            }
        }
        sun?.light.color = Self.uiColor(look.light(Self.sunColor))
        fill?.light.color = Self.uiColor(look.light(Self.fillColor))
        for (light, _) in dapples {
            light.light.color = Self.uiColor(look.light(Self.spotColor))
        }
        for layer in debris {
            guard var particles = layer.entity.components[ParticleEmitterComponent.self] else { continue }
            let color = look.light(Self.speckColor) * layer.brightness
            particles.mainEmitter.color = .constant(.single(Self.uiColor(color, alpha: layer.alpha)))
            layer.entity.components.set(particles)
        }
        if let wake, var particles = wake.components[ParticleEmitterComponent.self] {
            particles.mainEmitter.color = .constant(.single(Self.uiColor(look.light(Self.speckColor), alpha: 0.45)))
            wake.components.set(particles)
        }
    }

    private func withPalette(_ material: inout CustomMaterial) {
        if let paletteTexture { material.custom.texture = .init(paletteTexture) }
    }

    private static let paletteOptions = TextureResource.CreateOptions(semantic: .raw, mipmapsMode: .none)

    /// 6 x 1 texels: deep, mid, shallow water, rays, magenta marking it, and the tint (WaterPalette).
    private static func paletteImage(_ look: SceneLook) -> CGImage? {
        let colors = [look.deepWater, look.midWater, look.shallowWater, look.rays, SIMD3<Float>(1, 0, 1),
                      SIMD3<Float>(look.underwaterTint, 0, 0)]
        var bytes: [UInt8] = []
        for color in colors {
            for value in [color.x, color.y, color.z] {
                bytes.append(UInt8((min(max(value, 0), 1) * 255).rounded()))
            }
            bytes.append(255)
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let space = CGColorSpace(name: CGColorSpace.linearSRGB) else { return nil }
        return CGImage(
            width: colors.count, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: 4 * colors.count, space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }

    private static func uiColor(_ color: SIMD3<Float>, alpha: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat(color.x), green: CGFloat(color.y), blue: CGFloat(color.z), alpha: alpha)
    }

    private func setShadowsEnabled(_ enabled: Bool) {
        guard enabled != shadowsEnabled else { return }
        shadowsEnabled = enabled
        sun?.shadow = enabled ? DirectionalLightComponent.Shadow(maximumDistance: 2, depthBias: 1) : nil
    }

}
