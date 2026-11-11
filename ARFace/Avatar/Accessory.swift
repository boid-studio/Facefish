import Foundation
import RealityKit

/// Things the fish can wear (the hat button). Each is a part of the fish model named
/// `accessory_<name>` (the Blender object's name), maybe with a version number after it
/// (`accessory_mask2`), left out until it's put on. It may carry the
/// face's shape keys to move with the face, and bends with the body as she swims.
nonisolated enum Accessory: String, Codable, CaseIterable, Identifiable {
    case mask
    case brows
    case tophat
    case snorkel
    case helmet

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mask: "Gold mask"
        case .brows: "Brows"
        case .tophat: "Top hat"
        case .snorkel: "Snorkel mask"
        case .helmet: "Diving helmet"
        }
    }

    var systemImage: String {
        switch self {
        case .mask: "theatermasks"
        case .brows: "eyebrow"
        case .tophat: "hat.widebrim.fill"
        case .snorkel: "figure.open.water.swim"
        case .helmet: "circle.circle"
        }
    }

    /// How far (model units) a side fin covering an eye in a blush keeps off the face, so it lies
    /// over the accessory instead of cutting into it (fish's left, right).
    var coverClearance: SIMD2<Float> {
        switch self {
        case .mask: SIMD2(0.03, 0.06)   // the band on the left, the mask over the right eye
        case .brows: .zero              // the blush pose was solved with them on
        case .tophat: .zero             // on top of her head
        case .snorkel: SIMD2(0.12, 0.12)   // the glass stands well out from both eyes
        case .helmet: .zero             // around her, not on her
        }
    }

    /// Whether she wears it until someone takes it off (the brows were part of her face).
    var wornByDefault: Bool {
        switch self {
        case .mask: false
        case .brows: true
        case .tophat, .snorkel: false
        case .helmet: true
        }
    }

    /// Part of the surroundings rather than worn: it stays where it is while she moves (the diving
    /// helmet she swims in).
    var isSurroundings: Bool { self == .helmet }

    /// The part's name in the model.
    var partName: String { "accessory_\(rawValue)" }

    /// The accessory a model part is, if any: its name, maybe with a version number after it.
    static func part(named name: String) -> Accessory? {
        let name = name.lowercased()
        return allCases.first { accessory in
            guard name.hasPrefix(accessory.partName) else { return false }
            return name.dropFirst(accessory.partName.count).allSatisfy { $0.isNumber || $0 == "_" || $0 == "v" }
        }
    }

    /// This accessory's part in `model`, if it has one.
    @MainActor func find(in entity: Entity) -> Entity? {
        if Self.part(named: entity.name) == self { return entity }
        for child in entity.children {
            if let found = find(in: child) { return found }
        }
        return nil
    }
}
