import SwiftUI

/// Single home for all debug tooling. Presented with `.inspector`, which is a
/// trailing column in regular width and a resizable sheet in compact width.
struct DebugInspector: View {
    @State private var avatarSession = AvatarSession.shared

    @AppStorage("debug.section.tracking") private var trackingExpanded = true
    @AppStorage("debug.section.avatar") private var avatarExpanded = true
    @AppStorage("debug.section.audio") private var audioExpanded = true
    @AppStorage("debug.section.rendering") private var renderingExpanded = true
    @AppStorage("debug.section.animations") private var animationsExpanded = false
    @AppStorage("debug.section.externalDisplay") private var externalDisplayExpanded = false

    var body: some View {
        List {
            // Collapsed sections aren't rendered, so their timelines stop refreshing.
            Section("Tracking", isExpanded: $trackingExpanded) {
                TrackingDebugSection(tracker: avatarSession.tracker)
            }
            Section("Avatar", isExpanded: $avatarExpanded) {
                AvatarDebugSection(
                    model: avatarSession.avatarDebug,
                    rendersExternally: avatarSession.externalDisplayScene != nil
                )
            }
            Section("Audio", isExpanded: $audioExpanded) {
                AudioDebugSection(monitor: avatarSession.audioMonitor)
            }
            Section("Rendering", isExpanded: $renderingExpanded) {
                RenderingDebugSection(model: avatarSession.avatarDebug)
            }
            Section("Animations", isExpanded: $animationsExpanded) {
                AnimationsDebugSection(model: avatarSession.avatarDebug)
            }
            if let scene = avatarSession.externalDisplayScene {
                Section("External display", isExpanded: $externalDisplayExpanded) {
                    ExternalDisplayDebugSection(windowScene: scene)
                }
            }
        }
        .listStyle(.sidebar)
        .inspectorColumnWidth(min: 300, ideal: 360, max: 480)
        .presentationDetents([.fraction(0.35), .medium, .large])
        .presentationBackgroundInteraction(.enabled)
    }
}
