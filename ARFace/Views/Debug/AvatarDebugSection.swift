import SwiftUI

struct AvatarDebugSection: View {
    let model: AvatarDebugModel
    let rendersExternally: Bool

    var body: some View {
        LabeledContent("Rendered on", value: rendersExternally ? "External display" : "This device")

        if let controller = model.controller {
            TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                VStack(spacing: 4) {
                    LabeledContent("Targets bound", value: "\(controller.boundLocations.count)/52")
                }
                .monospacedDigit()
            }
        } else {
            Text("Avatar not loaded")
                .foregroundStyle(.secondary)
        }
    }
}

struct RenderingDebugSection: View {
    @Bindable var model: AvatarDebugModel
    @Environment(\.self) private var environment

    var body: some View {
        LabeledContent("Frame rate") {
            Text("\(model.framesPerSecond, specifier: "%.1f") FPS")
                .monospacedDigit()
        }
        LabeledContent("Phone temperature") {
            switch ProcessInfo.processInfo.thermalState {
            case .nominal: Text("Normal")
            case .fair: Text("Warm")
            case .serious: Text("Hot: easing off effects").foregroundStyle(.orange)
            case .critical: Text("Very hot: easing off effects").foregroundStyle(.red)
            @unknown default: Text("Unknown")
            }
        }

        // Laughing needs a smile, plus squinting eyes or a jaw/voice "ha-ha" rhythm.
        Toggle("Laugh detection", isOn: $model.laughDetectionEnabled)
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent("Laugh") {
                Text("\(Int(model.laughReadout.intensity * 100))%")
                    .monospacedDigit()
            }
            ProgressView(value: Double(min(max(model.laughReadout.intensity, 0), 1)))
            Text("smile \(model.laughReadout.smile, specifier: "%.2f")  squint \(model.laughReadout.squint, specifier: "%.2f")  jaw \(model.laughReadout.jawRhythm, specifier: "%.3f")  voice \(model.laughReadout.voiceRhythm, specifier: "%.3f")")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            LabeledContent("Big note") {
                Text("\(Int(model.laughReadout.bigNote * 100))%").monospacedDigit()
            }
        }

        VStack(alignment: .leading) {
            LabeledContent("Acting") {
                Text("\(model.acting, specifier: "%.2f")").monospacedDigit()
            }
            Slider(value: $model.acting, in: 0...1) { Text("Acting") }
        }

        ColorPicker("Water colour", selection: Binding(
            get: { Color(.sRGBLinear, red: Double(model.waterColor.x), green: Double(model.waterColor.y), blue: Double(model.waterColor.z)) },
            set: { color in
                let resolved = color.resolve(in: environment)
                model.waterColor = SIMD3(resolved.linearRed, resolved.linearGreen, resolved.linearBlue)
            }
        ), supportsOpacity: false)
        Button("Default water colour") { model.waterColor = SceneLook.defaultWater }
            .disabled(model.waterColor == SceneLook.defaultWater)
        Button("Save scene settings") { model.saveScene() }
        if let saved = model.sceneSavedAt {
            Text("Saved \(saved.formatted(date: .omitted, time: .shortened)). Loaded at launch.")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            Text("Scene changes are a preview until saved.")
                .font(.caption).foregroundStyle(.secondary)
        }
        VStack(alignment: .leading) {
            LabeledContent("White balance") {
                Text("\(model.whiteBalance, specifier: "%+.2f")").monospacedDigit()
            }
            Slider(value: $model.whiteBalance, in: -1...1) { Text("White balance") }
        }
        VStack(alignment: .leading) {
            LabeledContent("Vignette") {
                Text("\(model.vignette, specifier: "%.2f")  size \(model.vignetteSize, specifier: "%.2f")").monospacedDigit()
            }
            Slider(value: $model.vignette, in: 0...1) { Text("Vignette") }
            Slider(value: $model.vignetteSize, in: 0...1.5) { Text("Vignette size") }
            Slider(value: $model.vignetteSoftness, in: 0.1...2.5) { Text("Vignette softness") }
        }
        VStack(alignment: .leading) {
            LabeledContent("Background brightness") {
                Text("\(model.waterBrightness, specifier: "%.2f")").monospacedDigit()
            }
            Slider(value: $model.waterBrightness, in: 0...1.3) { Text("Background brightness") }
        }
        VStack(alignment: .leading) {
            LabeledContent("Bob with phone movement") {
                Text("\(model.motionReaction, specifier: "%.2f")").monospacedDigit()
            }
            Slider(value: $model.motionReaction, in: 0...2) { Text("Bob with phone movement") }
        }
        VStack(alignment: .leading) {
            LabeledContent("Debris / water motion") {
                Text("\(model.debrisAmount, specifier: "%.2f") / \(model.waterMotion, specifier: "%.2f")").monospacedDigit()
            }
            Slider(value: $model.debrisAmount, in: 0...2) { Text("Debris in the water") }
            Slider(value: $model.waterMotion, in: 0...2) { Text("Water motion") }
        }
        VStack(alignment: .leading) {
            LabeledContent("Distortion") {
                Text("\(model.distortion, specifier: "%.2f")").monospacedDigit()
            }
            Slider(value: $model.distortion, in: 0...1) { Text("Distortion") }
        }
        VStack(alignment: .leading) {
            LabeledContent("Field of view") {
                Text("\(model.fieldOfView, specifier: "%.0f")°").monospacedDigit()
            }
            Slider(value: $model.fieldOfView, in: 20...70) { Text("Field of view") }
        }

        VStack(alignment: .leading) {
            LabeledContent("Camera Z") {
                Text("\(model.cameraZ, specifier: "%.2f") m")
                    .monospacedDigit()
            }
            Slider(value: $model.cameraZ, in: 0.1...3) {
                Text("Camera Z")
            }
        }

        Toggle("Caustic shaders", isOn: $model.causticsEnabled)
        VStack(alignment: .leading) {
            LabeledContent("Caustic size") {
                Text("\(model.causticScale, specifier: "%.2f")x").monospacedDigit()
            }
            Slider(value: $model.causticScale, in: 0.25...4) { Text("Caustic size") }
        }
        VStack(alignment: .leading) {
            LabeledContent("Caustic speed") {
                Text("\(model.causticSpeed, specifier: "%.2f")x").monospacedDigit()
            }
            Slider(value: $model.causticSpeed, in: 0.1...4) { Text("Caustic speed") }
        }
        VStack(alignment: .leading) {
            LabeledContent("Caustic intensity") {
                Text("\(model.causticIntensity, specifier: "%.2f")x").monospacedDigit()
            }
            Slider(value: $model.causticIntensity, in: 0...3) { Text("Caustic intensity") }
        }
        VStack(alignment: .leading) {
            LabeledContent("Caustic angle") {
                Text("\(model.causticAngle, specifier: "%.0f")°").monospacedDigit()
            }
            Slider(value: $model.causticAngle, in: -60...60, step: 5) { Text("Caustic angle") }
        }
        Toggle("Ambient bubbles", isOn: $model.ambientBubblesEnabled)
        Toggle("Mouth bubbles", isOn: $model.mouthBubblesEnabled)
        Toggle("Audio bubbles", isOn: $model.audioBubblesEnabled)
        Toggle("Animated spotlights", isOn: $model.spotlightsEnabled)
        Toggle("Directional shadow", isOn: $model.shadowsEnabled)
        Toggle("Blend shapes", isOn: $model.blendShapesEnabled)
        Toggle("Fin animation", isOn: $model.finAnimationEnabled)
        Toggle("Eye movement", isOn: $model.eyeMovementEnabled)
        Toggle("Eyelids", isOn: $model.eyelidsEnabled)
        Toggle("Swim motion", isOn: $model.swimMotionEnabled)
        Toggle("Follow head", isOn: $model.headFollowEnabled)
    }
}

struct AnimationsDebugSection: View {
    let model: AvatarDebugModel

    @State private var filter = ""

    private var filteredAnimations: [AvatarAnimation] {
        guard !filter.isEmpty else { return model.animations }
        return model.animations.filter { $0.name.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        if model.animations.isEmpty {
            Text(model.controller == nil ? "Avatar not loaded" : "No animations available")
                .foregroundStyle(.secondary)
        } else {
            HStack {
                TextField("Filter", text: $filter)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Stop all", systemImage: "stop.fill") { model.stopAll() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
            }

            ForEach(filteredAnimations) { animation in
                HStack(spacing: 8) {
                    Text(animation.name)
                        .font(.caption)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button("Play once", systemImage: "play.fill") { model.playOnce(animation) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.bordered)

                    Toggle("Loop", isOn: Binding(
                        get: { model.loopingAnimationIDs.contains(animation.id) },
                        set: { model.setLooping(animation, enabled: $0) }
                    ))
                    .labelsHidden()
                }
            }
        }
    }
}
