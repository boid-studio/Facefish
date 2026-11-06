import Foundation
import simd

/// The scene's colours, set per cosplay setup (the control app's Scene tab): the water's colour and
/// the white balance of the whole image.
///
/// The scene was designed around one sea blue. Picking another water colour turns every water
/// colour (the depth gradient, the light rays, the haze on the fish, the lights, the specks, the
/// bubbles' reflections) by the same hue, saturation and brightness change, so the look holds
/// together in any colour. Colours are linear RGB.
nonisolated struct SceneLook: Equatable {
    /// The water at mid depth.
    var water = SceneLook.defaultWater
    /// -1 cool (bluer) ... 0 neutral ... +1 warm (redder), on the whole image.
    var whiteBalance: Float = 0
    /// Darkening toward the edges, 0 (off) ... 1 (black at the edge). It's round, measured from the
    /// middle in halves of the screen's narrow side: the same circle in portrait as on the round
    /// 1080 x 1080 display, whose edge is at 1.
    var vignette: Float = 0
    /// Where the darkening starts (0...1.5, halves of the narrow side), and how far further out it
    /// reaches full strength (a soft edge is wide).
    var vignetteSize: Float = 0.6
    var vignetteSoftness: Float = 1.2
    /// How light the water is, 0 (black) ... 1 (as designed) ... 1.3: the background, its light
    /// rays and the water's haze on the fish. The fish's own lighting stays.
    var brightness: Float = 1
    /// The image wavering as if seen through moving water, 0 (off) ... 1 (strong).
    var distortion: Float = 0

    static let defaultWater = SIMD3<Float>(0.02, 0.26, 0.44)

    /// The backdrop's depth gradient and the light rays, for the shaders (WaterPalette), as light
    /// as `brightness` says.
    var deepWater: SIMD3<Float> { recolored(SIMD3(0.0, 0.05, 0.14)) * lightness }
    var midWater: SIMD3<Float> { water * lightness }
    var shallowWater: SIMD3<Float> { recolored(SIMD3(0.18, 0.62, 0.78)) * lightness }
    var rays: SIMD3<Float> { recolored(SIMD3(0.35, 0.7, 0.8)) * lightness }
    private var lightness: Float { min(max(brightness, 0), 1.3) }

    /// A light or a speck: turned to the water's hue, but as bright as before.
    func light(_ color: SIMD3<Float>) -> SIMD3<Float> { recolored(color, keepsBrightness: true) }

    /// What a glass bubble reflects, below and above (GlassBubbles.metal).
    var bubbleEnvironment: (low: SIMD3<Float>, high: SIMD3<Float>) {
        (recolored(SIMD3(0.12, 0.3, 0.4)) * lightness, recolored(SIMD3(0.7, 0.9, 1.0), keepsBrightness: true))
    }

    /// Per-channel gains for the white balance, keeping the image's brightness.
    var whiteBalanceGains: SIMD3<Float> {
        let t = min(max(whiteBalance, -1), 1)
        let gains = SIMD3<Float>(1 + 0.22 * t, 1 + 0.03 * t, 1 - 0.22 * t)
        return gains / simd_dot(gains, SIMD3(0.2126, 0.7152, 0.0722))
    }

    /// `color` with the hue turned, and the saturation and brightness scaled, as the default water
    /// changes to `water`.
    private func recolored(_ color: SIMD3<Float>, keepsBrightness: Bool = false) -> SIMD3<Float> {
        guard water != Self.defaultWater else { return color }
        let from = Self.hsv(Self.defaultWater), to = Self.hsv(water)
        var hsv = Self.hsv(color)
        hsv.x = (hsv.x + to.x - from.x).truncatingRemainder(dividingBy: 1)
        if hsv.x < 0 { hsv.x += 1 }
        hsv.y = min(1, hsv.y * to.y / from.y)
        if !keepsBrightness { hsv.z = min(1, hsv.z * to.z / from.z) }
        return Self.rgb(hsv)
    }

    /// Hue (0...1), saturation, value.
    private static func hsv(_ c: SIMD3<Float>) -> SIMD3<Float> {
        let high = c.max(), low = c.min(), range = high - low
        guard range > 1e-6 else { return SIMD3(0, 0, high) }
        var hue: Float
        if high == c.x {
            hue = (c.y - c.z) / range
        } else if high == c.y {
            hue = 2 + (c.z - c.x) / range
        } else {
            hue = 4 + (c.x - c.y) / range
        }
        hue /= 6
        if hue < 0 { hue += 1 }
        return SIMD3(hue, range / high, high)
    }

    private static func rgb(_ hsv: SIMD3<Float>) -> SIMD3<Float> {
        let h = hsv.x * 6, s = hsv.y, v = hsv.z
        let sector = Int(h) % 6, f = h - Float(Int(h))
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        switch sector {
        case 0: return SIMD3(v, t, p)
        case 1: return SIMD3(q, v, p)
        case 2: return SIMD3(p, v, t)
        case 3: return SIMD3(p, q, v)
        case 4: return SIMD3(t, p, v)
        default: return SIMD3(v, p, q)
        }
    }
}

/// The scene's parts that can be switched on and off (the control app's Scene tab).
nonisolated enum SceneSwitch: String, Codable, CaseIterable, Identifiable {
    case caustics, ambientBubbles, mouthBubbles, audioBubbles, lightPatches, shadows

    var id: String { rawValue }

    var title: String {
        switch self {
        case .caustics: "Caustics"
        case .ambientBubbles: "Ambient bubbles"
        case .mouthBubbles: "Mouth bubbles"
        case .audioBubbles: "Voice bubbles"
        case .lightPatches: "Moving light patches"
        case .shadows: "Shadows"
        }
    }
}

/// Ready-made water colours for different setups.
nonisolated enum WaterPreset: String, CaseIterable, Identifiable {
    case ocean, lagoon, deepSea, kelp, sunset, violet

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ocean: "Ocean"
        case .lagoon: "Lagoon"
        case .deepSea: "Deep sea"
        case .kelp: "Kelp"
        case .sunset: "Sunset"
        case .violet: "Violet"
        }
    }

    /// Linear RGB at mid depth.
    var water: SIMD3<Float> {
        switch self {
        case .ocean: SceneLook.defaultWater
        case .lagoon: SIMD3(0.01, 0.30, 0.25)
        case .deepSea: SIMD3(0.01, 0.07, 0.2)
        case .kelp: SIMD3(0.07, 0.24, 0.07)
        case .sunset: SIMD3(0.42, 0.13, 0.09)
        case .violet: SIMD3(0.17, 0.06, 0.38)
        }
    }
}

/// One cosplay setup's scene, as the main app keeps it (saved on the phone, loaded at launch) and
/// the control app reads it on connecting: the main app is where it lives. Short keys, so it fits
/// one Bluetooth read.
nonisolated struct SceneSettings: Codable, Equatable {
    var water = SceneLook.defaultWater
    var whiteBalance: Float = 0
    var fieldOfView: Float = 35
    var cameraZ: Float = 0.75
    var vignette: Float = 0
    var vignetteSize: Float = 0.6
    var vignetteSoftness: Float = 1.2
    var brightness: Float = 1
    var causticIntensity: Float = 1
    var motionReaction: Float = 1
    var debrisAmount: Float = 1
    var waterMotion: Float = 1
    var distortion: Float = 0
    /// The effects switched off (SceneSwitch names).
    var off: [String] = []

    enum CodingKeys: String, CodingKey {
        case water = "w", whiteBalance = "wb", fieldOfView = "fov", cameraZ = "z", vignette = "v",
             vignetteSize = "vs", vignetteSoftness = "vf", brightness = "b", causticIntensity = "c",
             motionReaction = "m", debrisAmount = "d", waterMotion = "wm", distortion = "ds", off = "o"
    }

    init() {}

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SceneSettings.defaults
        water = try c.decodeIfPresent(SIMD3<Float>.self, forKey: .water) ?? d.water
        whiteBalance = try c.decodeIfPresent(Float.self, forKey: .whiteBalance) ?? d.whiteBalance
        fieldOfView = try c.decodeIfPresent(Float.self, forKey: .fieldOfView) ?? d.fieldOfView
        cameraZ = try c.decodeIfPresent(Float.self, forKey: .cameraZ) ?? d.cameraZ
        vignette = try c.decodeIfPresent(Float.self, forKey: .vignette) ?? d.vignette
        vignetteSize = try c.decodeIfPresent(Float.self, forKey: .vignetteSize) ?? d.vignetteSize
        vignetteSoftness = try c.decodeIfPresent(Float.self, forKey: .vignetteSoftness) ?? d.vignetteSoftness
        brightness = try c.decodeIfPresent(Float.self, forKey: .brightness) ?? d.brightness
        causticIntensity = try c.decodeIfPresent(Float.self, forKey: .causticIntensity) ?? d.causticIntensity
        motionReaction = try c.decodeIfPresent(Float.self, forKey: .motionReaction) ?? d.motionReaction
        debrisAmount = try c.decodeIfPresent(Float.self, forKey: .debrisAmount) ?? d.debrisAmount
        waterMotion = try c.decodeIfPresent(Float.self, forKey: .waterMotion) ?? d.waterMotion
        distortion = try c.decodeIfPresent(Float.self, forKey: .distortion) ?? d.distortion
        off = try c.decodeIfPresent([String].self, forKey: .off) ?? d.off
    }

    private static let defaults = SceneSettings()
}
