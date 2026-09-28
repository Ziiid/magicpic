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
    case polaroid
    case photobooth
    case photoboothMono

    public var id: String { rawValue }

    public var label: String {
        let locale = AppLanguage.current.locale
        switch self {
        case .none: return String(localized: "Inget", bundle: .module, locale: locale)
        case .blackAndWhite: return String(localized: "Svartvitt", bundle: .module, locale: locale)
        case .sepia: return String(localized: "Gammal bild", bundle: .module, locale: locale)
        case .xray: return String(localized: "Röntgen", bundle: .module, locale: locale)
        case .chrome: return String(localized: "Krom", bundle: .module, locale: locale)
        case .fade: return String(localized: "Blekt", bundle: .module, locale: locale)
        case .comic: return String(localized: "Serietidning", bundle: .module, locale: locale)
        case .thermal: return String(localized: "Värmekamera", bundle: .module, locale: locale)
        case .poster: return String(localized: "Poster", bundle: .module, locale: locale)
        // "Direktbild" - INTE "Polaroid" (upptaget av den riktiga, inramade
        // stilen nedan sedan 2026-09-26) - det här är bara CIPhotoEffectInstants
        // FÄRGLOOK, ingen ram/layout.
        case .instant: return String(localized: "Direktbild", bundle: .module, locale: locale)
        case .process: return String(localized: "Process", bundle: .module, locale: locale)
        case .tonal: return String(localized: "Tonal", bundle: .module, locale: locale)
        case .transfer: return String(localized: "Filmtransfer", bundle: .module, locale: locale)
        case .vignette: return String(localized: "Vinjett", bundle: .module, locale: locale)
        case .negative: return String(localized: "Negativ", bundle: .module, locale: locale)
        case .polaroid: return String(localized: "Polaroid", bundle: .module, locale: locale)
        case .photobooth: return String(localized: "Fotoautomat", bundle: .module, locale: locale)
        case .photoboothMono: return String(localized: "Fotoautomat (svartvitt)", bundle: .module, locale: locale)
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
