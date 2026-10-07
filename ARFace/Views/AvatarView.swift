import OSLog
import RealityKit
import RealityKitContent
import SwiftUI

struct AvatarView: View {
    let tracker: FaceTracker
    let mirrored: Bool
    var showsLoadError = true

    @State private var controller: AvatarController?
    @State private var updateSubscription: EventSubscription?
    @State private var loadError: String?
    @State private var isVisible = true
    @State private var sceneID = UUID()
    @State private var debugOwnerID = UUID()
    @State private var glassFrame = GlassBubbleFrame()

    private var avatarDebug: AvatarDebugModel { AvatarSession.shared.avatarDebug }

    var body: some View {
        RealityView { content in
            let loadingSceneID = sceneID
            content.camera = .virtual
            let screenSpaceGlass: Bool
            if #available(iOS 26.0, *) {
                do {
                    content.renderingEffects.customPostProcessing = .effect(try GlassBubbleEffect(frame: glassFrame))
                    screenSpaceGlass = true
                } catch {
                    Logger(subsystem: "ARFace", category: "GlassBubbles")
                        .error("Glass post-processing unavailable; using transparent spheres: \(error.localizedDescription)")
                    screenSpaceGlass = false
                }
            } else {
                screenSpaceGlass = false
            }

            let camera = PerspectiveCamera()
            camera.camera.fieldOfViewInDegrees = 35
            camera.position = [0, 0, avatarDebug.cameraZ]
            content.add(camera)

            do {
                let environment = try await Entity(
                    named: "UnderwaterScene",
                    in: realityKitContentBundle
                )
                try Task.checkCancellation()
                guard isVisible, sceneID == loadingSceneID else { return }
                let underwater = UnderwaterSceneController(scene: environment, screenSpaceGlass: screenSpaceGlass)
                content.add(environment)

                let model = try await Entity(named: "fish")
                try Task.checkCancellation()
                guard isVisible, sceneID == loadingSceneID else { return }
                underwater.applyCaustics(to: model)
                let controller = AvatarController(model: model, screenSpaceGlass: screenSpaceGlass)
                controller.mirrored = mirrored
                content.add(controller.sceneRoot)
                updateSubscription = content.subscribe(to: SceneEvents.Update.self) { event in
                    avatarDebug.recordFrame(deltaTime: event.deltaTime)
                    let options = avatarDebug.renderOptions
                    underwater.update(deltaTime: event.deltaTime, options: options)
                    controller.apply(tracker.snapshot(), deltaTime: event.deltaTime, options: options)
                    if screenSpaceGlass {
                        glassFrame.update(
                            spheres: underwater.glassSpheres + controller.glassSpheres,
                            cameraZ: camera.position.z
                        )
                    }
                }
                self.controller = controller
                avatarDebug.attach(owner: debugOwnerID, controller: controller, animations: model.animations())
            } catch is CancellationError {
                // Scene removal can cancel an in-flight asset load.
                return
            } catch {
                guard isVisible, sceneID == loadingSceneID else { return }
                loadError = "Couldn't load scene: \(error.localizedDescription)"
            }
        } update: { content in
            for case let camera as PerspectiveCamera in content.entities {
                camera.position.z = avatarDebug.cameraZ
            }
            controller?.mirrored = mirrored
        }
        .id(sceneID)
        .overlay {
            if showsLoadError, let loadError {
                ContentUnavailableView("No avatar", systemImage: "person.crop.circle.badge.exclamationmark", description: Text(loadError))
            }
        }
        .onAppear {
            if !isVisible {
                sceneID = UUID()
                loadError = nil
                isVisible = true
            }
        }
        .onDisappear {
            isVisible = false
            updateSubscription?.cancel()
            updateSubscription = nil
            avatarDebug.detach(owner: debugOwnerID)
            controller = nil
            glassFrame.update(spheres: [], cameraZ: 0)
        }
    }
}
