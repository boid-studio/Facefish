import RealityKit
import RealityKitContent
import SwiftUI

struct AvatarView: View {
    let tracker: FaceTracker
    let mirrored: Bool
    let showDebug: Bool
    var showsLoadError = true

    @State private var controller: AvatarController?
    @State private var updateSubscription: EventSubscription?
    @State private var loadError: String?

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
    }
}
