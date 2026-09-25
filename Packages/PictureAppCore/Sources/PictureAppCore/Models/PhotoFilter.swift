import Foundation

/// Färdiga bildstilar (som Bilder-appens filterval) - tillämpas på
/// originalbilden INNAN `ImageAdjustments` och Vision-analysen/
/// bakgrundsborttagningen (se `SearchViewModel.removeBackground()`), som
/// ett första, valfritt "stil"-lager.
public enum PhotoFilter: String, CaseIterable, Identifiable, Equatable {
    case none
    case blackAndWhite
    case sepia
    case xray
    case chrome
    case fade
    case comic
    case thermal
    case poster
    case instant

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .none: return "Inget"
        case .blackAndWhite: return "Svartvitt"
        case .sepia: return "Gammal bild"
        case .xray: return "Röntgen"
        case .chrome: return "Krom"
        case .fade: return "Blekt"
        case .comic: return "Serietidning"
        case .thermal: return "Värmekamera"
        case .poster: return "Poster"
        case .instant: return "Polaroid"
        }
    }

    public var systemImage: String {
        switch self {
        case .none: return "circle.slash"
        case .blackAndWhite: return "circle.lefthalf.filled"
        case .sepia: return "photo"
        case .xray: return "sparkles"
        case .chrome: return "sparkle"
        case .fade: return "cloud"
        case .comic: return "bubble.left"
        case .thermal: return "flame"
        case .poster: return "square.stack.3d.up"
        case .instant: return "camera.aperture"
        }
    }
}
