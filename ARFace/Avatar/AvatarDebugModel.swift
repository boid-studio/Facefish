import simd
import Foundation
import Observation
import RealityKit

struct AvatarRenderOptions {
    let causticsEnabled: Bool
    let causticScale: Float
    let causticSpeed: Float
    let causticIntensity: Float
    let causticAngle: Float
    let ambientBubblesEnabled: Bool
    let mouthBubblesEnabled: Bool
    let audioBubblesEnabled: Bool
    let spotlightsEnabled: Bool
    let shadowsEnabled: Bool
    let blendShapesEnabled: Bool
    let finAnimationEnabled: Bool
    let eyeMovementEnabled: Bool
    let eyelidsEnabled: Bool
    let swimMotionEnabled: Bool
    let headFollowEnabled: Bool
    let look: SceneLook
    /// The debris in the water: how much (0...2) and how much it moves (0...2).
    let debrisAmount: Float
    let waterMotion: Float
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
    /// What the laugh detector sees (AvatarController), for tuning.
    var laughReadout = LaughReadout()

    // The scene (the control app's Scene tab): one setup per show, kept by saveScene().
    var cameraZ: Float = 0.75
    /// The camera's vertical field of view (degrees).
    var fieldOfView: Float = 35
    /// The water's colour (linear RGB, SceneLook).
    var waterColor = SceneLook.defaultWater
    /// -1 cool ... +1 warm.
    var whiteBalance: Float = 0
    /// 0 off ... 1 black at the edge; where it starts (SceneLook).
    var vignette: Float = 0
    var vignetteSize: Float = 0.6
    var vignetteSoftness: Float = 1.2
    /// How light the water (background) is, 0 black ... 1 as designed ... 1.3 (SceneLook).
    var waterBrightness: Float = 1
    /// How much she bobs as the phone moves: 0 off, 1 slight, 2 more (AvatarController).
    var motionReaction: Float = 1
    /// How much debris floats in the water, and how lively the water moves it (0...2, 1 = default).
    var debrisAmount: Float = 1
    var waterMotion: Float = 1
    /// The image wavering as if seen through moving water, 0...1 (SceneLook).
    var distortion: Float = 0
    /// 0 = natural, 1 = big stage acting (AvatarController; set from the control app too).
    var acting: Float = 0
    /// Spotting laughter and playing it bigger (LaughDetector). Off: not reliable enough yet.
    var laughDetectionEnabled = false
    var causticsEnabled = true
    /// Multipliers on the caustic pattern size and animation speed (1 = default).
    var causticScale: Float = 1
    var causticSpeed: Float = 1
    var causticIntensity: Float = 1
    /// Degrees from straight down; positive tilts the light toward the viewer (body only).
    var causticAngle: Float = 0
    var ambientBubblesEnabled = true
    var mouthBubblesEnabled = true
    var audioBubblesEnabled = true
    var spotlightsEnabled = true
    var shadowsEnabled = true
    var blendShapesEnabled = true
    var finAnimationEnabled = true
    var eyeMovementEnabled = true
    var eyelidsEnabled = true
    var swimMotionEnabled = true
    var headFollowEnabled = true

    var renderOptions: AvatarRenderOptions {
        AvatarRenderOptions(
            causticsEnabled: causticsEnabled,
            causticScale: causticScale,
            causticSpeed: causticSpeed,
            causticIntensity: causticIntensity,
            causticAngle: causticAngle,
            ambientBubblesEnabled: ambientBubblesEnabled,
            mouthBubblesEnabled: mouthBubblesEnabled,
            audioBubblesEnabled: audioBubblesEnabled,
            spotlightsEnabled: spotlightsEnabled,
            shadowsEnabled: shadowsEnabled,
            blendShapesEnabled: blendShapesEnabled,
            finAnimationEnabled: finAnimationEnabled,
            eyeMovementEnabled: eyeMovementEnabled,
            eyelidsEnabled: eyelidsEnabled,
            swimMotionEnabled: swimMotionEnabled,
            headFollowEnabled: headFollowEnabled,
            look: SceneLook(water: waterColor, whiteBalance: whiteBalance, vignette: vignette,
                            vignetteSize: vignetteSize, vignetteSoftness: vignetteSoftness, brightness: waterBrightness, distortion: distortion),
            debrisAmount: debrisAmount,
            waterMotion: waterMotion
        )
    }

    /// A scene switch (the Scene tab).
    subscript(scene part: SceneSwitch) -> Bool {
        get {
            switch part {
            case .caustics: causticsEnabled
            case .ambientBubbles: ambientBubblesEnabled
            case .mouthBubbles: mouthBubblesEnabled
            case .audioBubbles: audioBubblesEnabled
            case .lightPatches: spotlightsEnabled
            case .shadows: shadowsEnabled
            }
        }
        set {
            switch part {
            case .caustics: causticsEnabled = newValue
            case .ambientBubbles: ambientBubblesEnabled = newValue
            case .mouthBubbles: mouthBubblesEnabled = newValue
            case .audioBubbles: audioBubblesEnabled = newValue
            case .lightPatches: spotlightsEnabled = newValue
            case .shadows: shadowsEnabled = newValue
            }
        }
    }

    /// The scene as it is now (SceneSettings): what the control app reads on connecting.
    var sceneSettings: SceneSettings {
        get {
            var scene = SceneSettings()
            scene.water = waterColor
            scene.whiteBalance = whiteBalance
            scene.fieldOfView = fieldOfView
            scene.cameraZ = cameraZ
            scene.vignette = vignette
            scene.vignetteSize = vignetteSize
            scene.vignetteSoftness = vignetteSoftness
            scene.brightness = waterBrightness
            scene.causticIntensity = causticIntensity
            scene.motionReaction = motionReaction
            scene.debrisAmount = debrisAmount
            scene.waterMotion = waterMotion
            scene.distortion = distortion
            scene.off = SceneSwitch.allCases.filter { !self[scene: $0] }.map(\.rawValue)
            return scene
        }
        set {
            waterColor = simd_clamp(newValue.water, .zero, .one)
            whiteBalance = min(max(newValue.whiteBalance, -1), 1)
            fieldOfView = min(max(newValue.fieldOfView, 15), 90)
            cameraZ = min(max(newValue.cameraZ, 0.1), 3)
            vignette = min(max(newValue.vignette, 0), 1)
            vignetteSize = min(max(newValue.vignetteSize, 0), 1.5)
            vignetteSoftness = min(max(newValue.vignetteSoftness, 0.05), 2.5)
            waterBrightness = min(max(newValue.brightness, 0), 1.3)
            causticIntensity = min(max(newValue.causticIntensity, 0), 3)
            motionReaction = min(max(newValue.motionReaction, 0), 2)
            debrisAmount = min(max(newValue.debrisAmount, 0), 2)
            waterMotion = min(max(newValue.waterMotion, 0), 2)
            distortion = min(max(newValue.distortion, 0), 1)
            for part in SceneSwitch.allCases { self[scene: part] = !newValue.off.contains(part.rawValue) }
        }
    }

    /// When the scene was last saved (nil: never, or not since launch).
    private(set) var sceneSavedAt: Date?

    /// Keeps the scene as it is now on this phone; it's loaded at the next launch. Changes before
    /// that are a preview.
    func saveScene() {
        guard let data = try? JSONEncoder().encode(sceneSettings) else { return }
        UserDefaults.standard.set(data, forKey: Self.sceneKey)
        sceneSavedAt = Date()
    }

    private static let sceneKey = "sceneSettings"
    @ObservationIgnored private var pendingSave: Task<Void, Never>?

    /// Saves the scene once changes settle (a slider drag saves once, at the end).
    func saveSceneSoon() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.saveScene()
        }
    }

    init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.sceneKey),
           let scene = try? JSONDecoder().decode(SceneSettings.self, from: data) {
            sceneSettings = scene
            // The distortion was on by default at first; it's off now unless set again.
            if !defaults.bool(forKey: "distortionOffV1") {
                defaults.set(true, forKey: "distortionOffV1")
                distortion = 0
                saveScene()
            }
        } else if defaults.object(forKey: "scene.cameraZ") != nil || defaults.object(forKey: "scene.waterColor") != nil {
            // Saved by an earlier version, one value each: carried over once.
            func float(_ key: String) -> Float? { (defaults.object(forKey: "scene." + key) as? NSNumber)?.floatValue }
            func bool(_ key: String) -> Bool? { defaults.object(forKey: "scene." + key) as? Bool }
            if let v = float("cameraZ") { cameraZ = v }
            if let v = float("fieldOfView") { fieldOfView = v }
            if let v = defaults.array(forKey: "scene.waterColor") as? [Float], v.count == 3 { waterColor = SIMD3(v[0], v[1], v[2]) }
            if let v = float("whiteBalance") { whiteBalance = v }
            if let v = float("vignette") { vignette = v }
            if let v = float("vignetteSize") { vignetteSize = v }
            if let v = float("vignetteSoftness") { vignetteSoftness = v }
            if let v = float("waterBrightness") { waterBrightness = v }
            if let v = float("motionReaction") { motionReaction = v }
            if let v = float("causticIntensity") { causticIntensity = v }
            if let v = bool("caustics") { causticsEnabled = v }
            if let v = bool("ambientBubbles") { ambientBubblesEnabled = v }
            if let v = bool("mouthBubbles") { mouthBubblesEnabled = v }
            if let v = bool("audioBubbles") { audioBubblesEnabled = v }
            if let v = bool("lightPatches") { spotlightsEnabled = v }
            if let v = bool("shadows") { shadowsEnabled = v }
            saveScene()
        }
    }

    @ObservationIgnored private var ownerID: UUID?
    @ObservationIgnored private var playbacks: [AvatarAnimation.ID: AnimationPlaybackController] = [:]
    @ObservationIgnored private var sampledFrameCount = 0
    @ObservationIgnored private var sampledDuration: TimeInterval = 0
    @ObservationIgnored private var sampledWorstFrame: TimeInterval = 0

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
        sampledWorstFrame = max(sampledWorstFrame, deltaTime)
        guard sampledDuration >= 0.5 else { return }

        framesPerSecond = Double(sampledFrameCount) / sampledDuration
        sampledFrameCount = 0
        sampledDuration = 0
        sampledWorstFrame = 0
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
