import SwiftUI

/// The main phone's controls, out of the fish's way: one button in the corner that slides up a
/// glassy drawer: her actions and what she wears in three tabs, one row each, and settings.
/// It stays open through taps; tap outside it or drag it down to close.
struct ActionDrawer: View {
    /// The fish is loaded: actions and accessories work.
    let isReady: Bool
    @State private var avatarSession = AvatarSession.shared
    @State private var isOpen = false
    @State private var dragOffset: CGFloat = 0
    @State private var taps = 0
    @State private var tab = Tab.swim
    @Namespace private var tabSpace

    private struct Action: Identifiable {
        let title: String
        let systemImage: String
        let move: SwimMove
        /// Lit while on (Hide, Play dead).
        var isOn = false
        var id: String { title }
    }

    private var groups: [(title: String, actions: [Action])] {
        [
            ("Swim", [
                Action(title: "Lap", systemImage: "point.forward.to.point.capsulepath", move: .lap),
                Action(title: "Spin", systemImage: "rotate.3d", move: .spin),
                Action(title: "Loop", systemImage: "arrow.clockwise", move: .loop),
            ]),
            ("Feelings", [
                Action(title: "Blush", systemImage: "heart", move: .blush),
                Action(title: "Laugh", systemImage: "face.smiling", move: .laugh),
                Action(title: "Fart", systemImage: "wind", move: .fart),
            ]),
            ("Gags", [
                Action(title: "Stare", systemImage: "eyes", move: .stare),
                Action(title: "Shush", systemImage: "hand.point.up", move: .shush),
                Action(title: "Bubbles", systemImage: "bubbles.and.sparkles", move: .bubbles),
            ]),
            ("Stage", [
                avatarSession.fishHidden
                    ? Action(title: "Show", systemImage: "eye", move: .show, isOn: true)
                    : Action(title: "Hide", systemImage: "eye.slash", move: .hide),
                avatarSession.fishPlaysDead
                    ? Action(title: "Wake up", systemImage: "sun.max", move: .wakeUp, isOn: true)
                    : Action(title: "Play dead", systemImage: "zzz", move: .playDead),
            ]),
        ]
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if isOpen {
                // A tap anywhere else closes it.
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture { close() }
                drawer
                    .offset(y: max(dragOffset, 0))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                openButton
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .ignoresSafeArea(edges: .bottom)   // down by the screen's edge, under the fish
        .environment(\.colorScheme, .dark)   // dark glass, with the water
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: isOpen)
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
    }

    private var openButton: some View {
        Button {
            taps += 1
            isOpen = true
        } label: {
            Image(systemName: "fish.fill")
                .font(.title2)
                .frame(width: 60, height: 60)
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .glass(Circle())
        .foregroundStyle(.primary)
        .padding(.trailing, 20)
        .padding(.bottom, 44)
        .accessibilityLabel("Actions")
    }

    /// The drawer's tabs, each one row high, so it stays low under the fish.
    private enum Tab: String, CaseIterable, Identifiable {
        case swim = "Swim & feelings", gags = "Gags & stage", wear = "Wear"
        var id: Self { self }
        var groupTitles: [String] {
            switch self {
            case .swim: ["Swim", "Feelings"]
            case .gags: ["Gags", "Stage"]
            case .wear: []
            }
        }
    }

    private var drawer: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Group {
                if tab == .wear {
                    wearRow
                } else {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(groups.filter { tab.groupTitles.contains($0.title) }, id: \.title) { group in
                            VStack(alignment: .leading, spacing: 6) {
                                sectionTitle(group.title)
                                HStack(spacing: 6) {
                                    ForEach(group.actions) { action in tile(action) }
                                    // Keeps the tiles the same width in a shorter row.
                                    ForEach(group.actions.count..<3, id: \.self) { _ in
                                        Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            // The same height on every tab, so switching doesn't make it jump.
            .frame(height: 82, alignment: .top)
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 14)
        .frame(maxWidth: 520)
        .glass(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .foregroundStyle(.primary)
        .disabled(!isReady)
    }

    private var wearRow: some View {
        Group {
            if avatarSession.availableAccessories.isEmpty {
                Text("Nothing to wear on this fish").font(.footnote).foregroundStyle(.secondary)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    FlowLayout(spacing: 6) {
                        ForEach(avatarSession.availableAccessories) { accessory in chip(accessory) }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The grabber (drag it down, or tap outside, to close), the tabs and settings.
    private var header: some View {
        VStack(spacing: 6) {
            Capsule()
                .fill(.secondary.opacity(0.6))
                .frame(width: 36, height: 4)
            HStack(spacing: 8) {
                tabBar
                Spacer(minLength: 0)
                roundButton("slider.horizontal.3", label: "Settings") {
                    close()
                    avatarSession.showDebug = true
                }
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { dragOffset = $0.translation.height }
                .onEnded { value in
                    if value.translation.height > 60 || value.predictedEndTranslation.height > 160 {
                        close()
                    }
                    withAnimation(.spring) { dragOffset = 0 }
                }
        )
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(Tab.allCases) { item in
                Button {
                    taps += 1
                    withAnimation(.snappy(duration: 0.22)) { tab = item }
                } label: {
                    Text(item.rawValue)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(tab == item ? .primary : .secondary)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 12)
                        .frame(minHeight: 36)
                        .background {
                            if tab == item {
                                Capsule().fill(.white.opacity(0.22)).matchedGeometryEffect(id: "tab", in: tabSpace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(3)
        .background(.white.opacity(0.08), in: Capsule())
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
    }

    private func tile(_ action: Action) -> some View {
        Button {
            taps += 1
            avatarSession.pendingMoves.append(action.move)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: action.systemImage).font(.title3).frame(height: 24)
                Text(action.title).font(.caption2.weight(.medium)).lineLimit(1).minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(
                action.isOn ? AnyShapeStyle(.tint.opacity(0.45)) : AnyShapeStyle(.white.opacity(0.12)),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(action.title)
    }

    private func chip(_ accessory: Accessory) -> some View {
        let worn = avatarSession.wornAccessories.contains(accessory)
        return Button {
            taps += 1
            if worn {
                avatarSession.wornAccessories.remove(accessory)
            } else {
                avatarSession.wornAccessories.insert(accessory)
            }
        } label: {
            Label(accessory.title, systemImage: worn ? "checkmark" : accessory.systemImage)
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(
                    worn ? AnyShapeStyle(.tint.opacity(0.45)) : AnyShapeStyle(.white.opacity(0.12)),
                    in: Capsule()
                )
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(worn ? .isSelected : [])
    }

    private func roundButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 40, height: 40)
                .background(.white.opacity(0.12), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }

    private func close() {
        isOpen = false
        dragOffset = 0
    }
}

/// Lays its views out in rows, wrapping onto the next when one is full.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var y: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

/// A press that answers at once: shrinks and dims a little while held.
private struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension View {
    /// Liquid glass where the system has it, frosted material before.
    @ViewBuilder
    func glass(_ shape: some Shape) -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
        }
    }
}
