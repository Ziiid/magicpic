import Foundation

/// Formen slutbilden beskärs till. Allt utom `.rectangle` beskär först till
/// kvadrat (centrerat) innan formen läggs på - annars blir cirklar/polygoner
/// skeva på en liggande eller stående bild, precis som profilbilder på
/// sociala medier alltid utgår från en kvadratisk beskärning.
public enum OutputShape: String, CaseIterable, Identifiable, Equatable {
    case rectangle
    case square
    case roundedSquare
    case circle
    case hexagon
    case octagon

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .rectangle: return "Rektangel"
        case .square: return "Kvadrat"
        case .roundedSquare: return "Avrundad kvadrat"
        case .circle: return "Cirkel"
        case .hexagon: return "Hexagon"
        case .octagon: return "Oktagon"
        }
    }

    public var systemImage: String {
        switch self {
        case .rectangle: return "rectangle"
        case .square: return "square"
        case .roundedSquare: return "app"
        case .circle: return "circle"
        case .hexagon: return "hexagon"
        case .octagon: return "octagon"
        }
    }
}
