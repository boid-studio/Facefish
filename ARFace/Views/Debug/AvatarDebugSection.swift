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

    var body: some View {
        LabeledContent("Frame rate") {
            Text("\(model.framesPerSecond, specifier: "%.1f") FPS")
                .monospacedDigit()
        }

        // Laughing needs a smile, plus squinting eyes or a jaw/voice "ha-ha" rhythm.
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
