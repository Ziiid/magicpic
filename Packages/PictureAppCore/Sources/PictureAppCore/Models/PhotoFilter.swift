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
    case process
    case tonal
    case transfer
    case vignette
    case negative
    case silhouette
    case polaroid
    case photobooth
    case photoboothMono

    public var id: String { rawValue }

    public var label: String {
        let locale = AppLanguage.current.locale
        switch self {
        case .none: return L("Inget")
        case .blackAndWhite: return L("Svartvitt")
        case .sepia: return L("Gammal bild")
        case .xray: return L("Röntgen")
        case .chrome: return L("Krom")
        case .fade: return L("Blekt")
        case .comic: return L("Serietidning")
        case .thermal: return L("Värmekamera")
        case .poster: return L("Poster")
        // "Direktbild" - INTE "Polaroid" (upptaget av den riktiga, inramade
        // stilen nedan sedan 2026-09-26) - det här är bara CIPhotoEffectInstants
        // FÄRGLOOK, ingen ram/layout.
        case .instant: return L("Direktbild")
        case .process: return L("Process")
        case .tonal: return L("Tonal")
        case .transfer: return L("Filmtransfer")
        case .vignette: return L("Vinjett")
        case .negative: return L("Negativ")
        case .silhouette: return L("Siluett")
        case .polaroid: return L("Polaroid")
        case .photobooth: return L("Fotoautomat")
        case .photoboothMono: return L("Fotoautomat (svartvitt)")
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
        case .process: return "bolt.fill"
        case .tonal: return "moon.fill"
        case .transfer: return "film"
        case .vignette: return "viewfinder"
        case .negative: return "circle.righthalf.filled"
        case .silhouette: return "person.fill"
        case .polaroid: return "photo.artframe"
        case .photobooth: return "rectangle.grid.1x2.fill"
        case .photoboothMono: return "rectangle.grid.1x2"
        }
    }

    /// `true` för stilar som INTE bara är ett färgfilter utan även bygger om
    /// själva LAYOUTEN (ram/flerbildsremsa - ANDRA bilddimensioner/
    /// bildförhållande än originalet). Används av:
    /// - `SearchViewModel.applyPipeline` (lägger `layoutWrap` EFTER
    ///   bakgrundskompositering/formbeskärning, inte före - annars hamnar
    ///   Visions mask fel mot den nya, större bilden).
    /// - `DetailPanel` (visar resultatet som en vanlig, oklippt bild istället
    ///   för i den kvadrat-/formklippande `SubjectFramingCanvas` - en hög,
    ///   smal fotoautomat-remsa blev annars beskuren till bara mitten av
    ///   remsan när den tvingades in i en kvadrat, upptäckt 2026-09-26).
    public var isLayoutStyle: Bool {
        switch self {
        case .polaroid, .photobooth, .photoboothMono: return true
        default: return false
        }
    }
}
