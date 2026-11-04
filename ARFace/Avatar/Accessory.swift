import Foundation

/// Things the fish can wear (the hat button). Each is a part of the fish model named
/// `accessory_<name>` (the Blender object's name), left out until it's put on. It may carry the
/// face's shape keys to move with the face, and bends with the body as she swims.
nonisolated enum Accessory: String, Codable, CaseIterable, Identifiable {
    case mask

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mask: "Mask"
        }
    }

    var systemImage: String {
        switch self {
        case .mask: "theatermasks"
        }
    }

    /// The part's name in the model.
    var partName: String { "accessory_\(rawValue)" }

    /// The accessory a model part (or the part it's in) is, if any.
    static func part(named name: String) -> Accessory? {
        allCases.first { $0.partName.caseInsensitiveCompare(name) == .orderedSame }
    }
}
