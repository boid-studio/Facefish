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
    @State private var viewAspect: Float = 0.46

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
            camera.camera.fieldOfViewInDegrees = avatarDebug.fieldOfView
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
                controller.cameraFieldOfView = camera.camera.fieldOfViewInDegrees
                controller.viewAspect = viewAspect
                content.add(controller.sceneRoot)
                updateSubscription = content.subscribe(to: SceneEvents.Update.self) { event in
                    let started = CACurrentMediaTime()
                    defer {
                        // What this frame's update cost, and once a second the summary (Benchmark).
                        PerformanceMetrics.shared.recordUpdate(ms: (CACurrentMediaTime() - started) * 1000)
                        if let sample = PerformanceMetrics.shared.sampleIfDue() { Benchmark.log(sample) }
                    }
                    avatarDebug.recordFrame(deltaTime: event.deltaTime)
                    for part in Benchmark.switchedOff where avatarDebug[scene: part] { avatarDebug[scene: part] = false }
                    let options = avatarDebug.renderOptions
                    controller.cameraDistance = camera.position.z   // the zoom
                    controller.phoneAcceleration = MotionTracker.shared.latest
                        .map { tracker.correctedMotion($0).acceleration } ?? .zero
                    controller.motionReaction = avatarDebug.motionReaction
                    underwater.phoneAcceleration = controller.phoneAcceleration
                    underwater.cameraZ = camera.position.z
                    underwater.stir(at: controller.fishPosition, speed: controller.swimSpeed)
                    controller.cameraFieldOfView = camera.camera.fieldOfViewInDegrees
                    // A hot phone throttles, and face tracking stutters first: ease off the extras.
                    let hot = ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue
                    underwater.easesOff = hot
                    glassFrame.update(look: options.look, fringe: !hot)
                    underwater.update(deltaTime: event.deltaTime, options: options)
                    controller.apply(
                        tracker.snapshot(),
                        audio: AvatarSession.shared.audioMonitor.snapshot(),
                        deltaTime: event.deltaTime,
                        options: options
                    )
                    if screenSpaceGlass {
                        let spheres = underwater.glassSpheres + controller.glassSpheres
                        PerformanceMetrics.shared.recordBubbles(spheres.count)
                        glassFrame.update(spheres: spheres, cameraZ: camera.position.z)
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
                camera.camera.fieldOfViewInDegrees = avatarDebug.fieldOfView
            }
            controller?.mirrored = mirrored
        }
        .onGeometryChange(for: Float.self) { proxy in
            proxy.size.height > 0 ? Float(proxy.size.width / proxy.size.height) : 0.46
        } action: { aspect in
            viewAspect = aspect
            controller?.viewAspect = aspect
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
