import RealityKit
import RealityKitContent
import SwiftUI

private struct AvatarAnimation: Identifiable {
    let id = UUID()
    let name: String
    let entity: Entity
    let resource: AnimationResource
}

private extension Entity {
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

struct AvatarView: View {
    let tracker: FaceTracker
    let mirrored: Bool
    let showDebug: Bool
    var showsLoadError = true

    @State private var controller: AvatarController?
    @State private var updateSubscription: EventSubscription?
    @State private var loadError: String?
    @State private var animations: [AvatarAnimation] = []
    @State private var animationControllers: [AvatarAnimation.ID: AnimationPlaybackController] = [:]
    @State private var loopingAnimationIDs: Set<AvatarAnimation.ID> = []

    var body: some View {
        RealityView { content in
            content.camera = .virtual

            let camera = PerspectiveCamera()
            camera.camera.fieldOfViewInDegrees = 35
            camera.position = [0, 0, 0.75]
            content.add(camera)

            do {
                let environment = try await Entity(
                    named: "UnderwaterScene",
                    in: realityKitContentBundle
                )
                let underwater = UnderwaterSceneController(scene: environment)
                content.add(environment)

                let model = try await Entity(named: "fish")
                animations = model.animations()
                underwater.applyCaustics(to: model)
                let controller = AvatarController(model: model)
                controller.mirrored = mirrored
                content.add(controller.root)
                updateSubscription = content.subscribe(to: SceneEvents.Update.self) { event in
                    underwater.update(deltaTime: event.deltaTime)
                    controller.apply(tracker.snapshot(), deltaTime: event.deltaTime)
                }
                self.controller = controller
            } catch {
                loadError = "Couldn't load scene: \(error.localizedDescription)"
            }
        } update: { _ in
            controller?.mirrored = mirrored
        }
        .overlay {
            if showsLoadError, let loadError {
                ContentUnavailableView("No avatar", systemImage: "person.crop.circle.badge.exclamationmark", description: Text(loadError))
            } else if showDebug, let controller {
                TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Avatar targets: \(controller.boundLocations.count)/52")
                        Text("Applied jawOpen: \(controller.appliedJawOpen, format: .number.precision(.fractionLength(2)))")
                    }
                    .font(.caption.monospaced())
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding()
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if showDebug, controller != nil {
                AnimationDebugView(
                    animations: animations,
                    loopingAnimationIDs: loopingAnimationIDs,
                    playOnce: playOnce,
                    setLooping: setLooping
                )
                .padding(.trailing, 12)
                .padding(.bottom, 64)
            }
        }
    }

    private func playOnce(_ animation: AvatarAnimation) {
        animationControllers[animation.id]?.stop()
        loopingAnimationIDs.remove(animation.id)
        animationControllers[animation.id] = animation.entity.playAnimation(animation.resource)
    }

    private func setLooping(_ animation: AvatarAnimation, enabled: Bool) {
        animationControllers[animation.id]?.stop()
        if enabled {
            animationControllers[animation.id] = animation.entity.playAnimation(animation.resource.repeat())
            loopingAnimationIDs.insert(animation.id)
        } else {
            animationControllers.removeValue(forKey: animation.id)
            loopingAnimationIDs.remove(animation.id)
        }
    }
}

private struct AnimationDebugView: View {
    let animations: [AvatarAnimation]
    let loopingAnimationIDs: Set<AvatarAnimation.ID>
    let playOnce: (AvatarAnimation) -> Void
    let setLooping: (AvatarAnimation, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Animations")
                .font(.headline)

            if animations.isEmpty {
                Text("No animations available")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(animations) { animation in
                            HStack(spacing: 8) {
                                Text(animation.name)
                                    .font(.caption)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Button {
                                    playOnce(animation)
                                } label: {
                                    Image(systemName: "play.fill")
                                }
                                .buttonStyle(.bordered)
                                .accessibilityLabel("Play once")

                                Toggle("Loop", isOn: Binding(
                                    get: { loopingAnimationIDs.contains(animation.id) },
                                    set: { setLooping(animation, $0) }
                                ))
                                .labelsHidden()
                                .accessibilityLabel("Loop")
                            }
                        }
                    }
                }
                .frame(maxHeight: 240)
            }
        }
        .frame(width: 320)
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
