import Foundation
import Observation
import RealityKit

struct AvatarRenderOptions {
    let causticsEnabled: Bool
    let ambientBubblesEnabled: Bool
    let mouthBubblesEnabled: Bool
    let spotlightsEnabled: Bool
    let shadowsEnabled: Bool
    let blendShapesEnabled: Bool
    let finAnimationEnabled: Bool
}

struct AvatarAnimation: Identifiable {
    let id = UUID()
    let name: String
    let entity: Entity
    let resource: AnimationResource
}

extension Entity {
    func animations(path: String? = nil) -> [AvatarAnimation] {
        let entityName = name.isEmpty ? "Unnamed entity" : name
        let currentPath = path.map { "\($0) / \(entityName)" } ?? entityName
        let localAnimations = availableAnimations.enumerated().map { index, resource -> AvatarAnimation in
            let animationName = resource.name.flatMap { $0.isEmpty ? nil : $0 } ?? "Animation \(index + 1)"
            return AvatarAnimation(
                name: "\(currentPath) - \(animationName)",
                entity: self,
                resource: resource
            )
        }
        return localAnimations + children.flatMap { $0.animations(path: currentPath) }
    }
}

/// Debug state for whichever `AvatarView` most recently loaded its scene
/// (the phone or the external display), so the debug inspector can drive it.
@Observable
final class AvatarDebugModel {
    private(set) var controller: AvatarController?
    private(set) var animations: [AvatarAnimation] = []
    private(set) var loopingAnimationIDs: Set<AvatarAnimation.ID> = []
    private(set) var framesPerSecond: Double = 0

    var causticsEnabled = true
    var ambientBubblesEnabled = true
    var mouthBubblesEnabled = true
    var spotlightsEnabled = true
    var shadowsEnabled = true
    var blendShapesEnabled = true
    var finAnimationEnabled = true

    var renderOptions: AvatarRenderOptions {
        AvatarRenderOptions(
            causticsEnabled: causticsEnabled,
            ambientBubblesEnabled: ambientBubblesEnabled,
            mouthBubblesEnabled: mouthBubblesEnabled,
            spotlightsEnabled: spotlightsEnabled,
            shadowsEnabled: shadowsEnabled,
            blendShapesEnabled: blendShapesEnabled,
            finAnimationEnabled: finAnimationEnabled
        )
    }

    @ObservationIgnored private var ownerID: UUID?
    @ObservationIgnored private var playbacks: [AvatarAnimation.ID: AnimationPlaybackController] = [:]
    @ObservationIgnored private var sampledFrameCount = 0
    @ObservationIgnored private var sampledDuration: TimeInterval = 0

    func attach(owner: UUID, controller: AvatarController, animations: [AvatarAnimation]) {
        stopAll()
        ownerID = owner
        self.controller = controller
        self.animations = animations
    }

    func detach(owner: UUID) {
        guard ownerID == owner else { return }
        stopAll()
        ownerID = nil
        controller = nil
        animations = []
        framesPerSecond = 0
        sampledFrameCount = 0
        sampledDuration = 0
    }

    func recordFrame(deltaTime: TimeInterval) {
        guard deltaTime.isFinite, deltaTime > 0 else { return }
        sampledFrameCount += 1
        sampledDuration += deltaTime
        guard sampledDuration >= 0.5 else { return }

        framesPerSecond = Double(sampledFrameCount) / sampledDuration
        sampledFrameCount = 0
        sampledDuration = 0
    }

    func playOnce(_ animation: AvatarAnimation) {
        playbacks[animation.id]?.stop()
        loopingAnimationIDs.remove(animation.id)
        playbacks[animation.id] = animation.entity.playAnimation(animation.resource)
    }

    func setLooping(_ animation: AvatarAnimation, enabled: Bool) {
        playbacks[animation.id]?.stop()
        if enabled {
            playbacks[animation.id] = animation.entity.playAnimation(animation.resource.repeat())
            loopingAnimationIDs.insert(animation.id)
        } else {
            playbacks.removeValue(forKey: animation.id)
            loopingAnimationIDs.remove(animation.id)
        }
    }

    func stopAll() {
        for playback in playbacks.values {
            playback.stop()
        }
        playbacks.removeAll()
        loopingAnimationIDs.removeAll()
    }
}
