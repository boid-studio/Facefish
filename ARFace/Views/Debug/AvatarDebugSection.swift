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
                    LabeledContent("Applied jawOpen") {
                        Text(controller.appliedJawOpen, format: .number.precision(.fractionLength(2)))
                    }
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

        VStack(alignment: .leading) {
            LabeledContent("Camera Z") {
                Text("\(model.cameraZ, specifier: "%.2f") m")
                    .monospacedDigit()
            }
            Slider(value: $model.cameraZ, in: 0.1...3, step: 0.01) {
                Text("Camera Z")
            }
        }

        Toggle("Caustic shaders", isOn: $model.causticsEnabled)
        Toggle("Ambient bubbles", isOn: $model.ambientBubblesEnabled)
        Toggle("Mouth bubbles", isOn: $model.mouthBubblesEnabled)
        Toggle("Animated spotlights", isOn: $model.spotlightsEnabled)
        Toggle("Directional shadow", isOn: $model.shadowsEnabled)
        Toggle("Blend shapes", isOn: $model.blendShapesEnabled)
        Toggle("Fin animation", isOn: $model.finAnimationEnabled)
        Toggle("Eye movement", isOn: $model.eyeMovementEnabled)
        Toggle("Eyelids", isOn: $model.eyelidsEnabled)
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
