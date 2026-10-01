import RealityKit

enum UnderwaterSceneController {
    static func prepare(_ scene: Entity) {
        guard let emitterEntity = scene.findEntity(named: "BubbleEmitter") else { return }

        var component = ParticleEmitterComponent()
        component.emitterShape = .box
        component.birthLocation = .volume
        component.emitterShapeSize = [0.35, 0.04, 0.18]
        component.birthDirection = .local
        component.emissionDirection = [0, 1, 0]
        component.speed = 0.035
        component.speedVariation = 0.015

        var particles = component.mainEmitter
        particles.birthRate = 18
        particles.birthRateVariation = 8
        particles.lifeSpan = 5
        particles.lifeSpanVariation = 1.5
        particles.size = 0.003
        particles.sizeVariation = 0.002
        particles.acceleration = [0, 0.012, 0]
        particles.dampingFactor = 0.05
        particles.noiseStrength = 0.015
        particles.noiseScale = 0.08
        particles.noiseAnimationSpeed = 0.3
        particles.opacityCurve = .gradualFadeInOut
        particles.blendMode = .alpha
        component.mainEmitter = particles

        emitterEntity.components.set(component)
    }
}
