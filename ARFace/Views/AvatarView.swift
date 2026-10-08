import OSLog
import RealityKit
import RealityKitContent
import SwiftUI

struct AvatarView: View {
    let tracker: FaceTracker
    let mirrored: Bool
    @Binding var isReady: Bool
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
                    controller.apply(
                        tracker.snapshot(),
                        audio: AvatarSession.shared.audioMonitor.snapshot(),
                        deltaTime: event.deltaTime,
                        options: options
                    )
                    if screenSpaceGlass {
                        glassFrame.update(
                            spheres: underwater.glassSpheres + controller.glassSpheres,
                            cameraZ: camera.position.z
                        )
                    }
                }
                self.controller = controller
                avatarDebug.attach(owner: debugOwnerID, controller: controller, animations: model.animations())
                isReady = true
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
                ContentUnavailableView(
                    "No avatar",
                    systemImage: "person.crop.circle.badge.exclamationmark",
                    description: Text(loadError)
                )
                .transition(.opacity)
            } else if !isReady, loadError == nil {
                AvatarLoadingView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: isReady)
        .onAppear {
            if !isVisible {
                sceneID = UUID()
                loadError = nil
                isVisible = true
            }
            if controller == nil {
                isReady = false
            }
        }
        .onDisappear {
            isVisible = false
            isReady = false
            updateSubscription?.cancel()
            updateSubscription = nil
            avatarDebug.detach(owner: debugOwnerID)
            controller = nil
            glassFrame.update(spheres: [], cameraZ: 0)
        }
    }

    private struct AvatarLoadingView: View {
        var body: some View {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.015, green: 0.12, blue: 0.2),
                        Color(red: 0.005, green: 0.035, blue: 0.08),
                        .black
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Circle()
                    .fill(Color.cyan.opacity(0.16))
                    .frame(width: 280, height: 280)
                    .blur(radius: 90)
                    .offset(y: -90)

                VStack(spacing: 18) {
                    Image(systemName: "fish.fill")
                        .font(.system(size: 56, weight: .medium))
                        .foregroundStyle(Color.cyan.opacity(0.9))
                        .shadow(color: .cyan.opacity(0.45), radius: 22)
                        .accessibilityHidden(true)

                    Text("Facefish")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)

                    ProgressView()
                        .tint(.cyan)
                        .padding(.top, 8)
                        .accessibilityLabel("Loading")

                    Text("PREPARING YOUR AQUARIUM")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .tracking(2.2)
                        .foregroundStyle(.white.opacity(0.62))
                }
                .padding(32)
            }
            .ignoresSafeArea()
            .preferredColorScheme(.dark)
        }
    }
}
