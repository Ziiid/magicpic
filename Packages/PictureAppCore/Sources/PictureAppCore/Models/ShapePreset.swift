import CoreGraphics
import Foundation

/// Ett val i formväljaren - antingen en PRAKTISK genväg (t.ex. "LinkedIn-
/// profil", fast bildförhållande OCH fast exportpixelstorlek) eller en
/// GENERISK geometrisk form (`OutputShape.allCases` - Rektangel/Kvadrat/
/// Avrundad kvadrat/Cirkel/Hexagon/Oktagon, fri storlek härledd från
/// källbilden, precis som innan den här typen fanns). Medvetet EN typ för
/// båda - siluetten (`contour`) och "vilket bildförhållande/pixelmål"
/// (`aspectRatio`/`pixelSize`) var redan två separata begrepp i koden
/// (`ShapeCropService`), så de praktiska genvägarna är bara nya
/// KOMBINATIONER av samma två begrepp, ingen parallell modell.
public struct ShapePreset: Identifiable, Equatable {
    public let id: String
    public let contour: OutputShape
    /// `nil` = behåll källbildens EGNA bildförhållande (bara Rektangel) -
    /// annars bildförhållandet kanvasen beskärs till, se
    /// `ShapeCropService.canvasSize(for:sourceSize:)`.
    public let aspectRatio: CGFloat?
    /// `nil` = härled kanvasens pixelstorlek från källbilden (de generiska
    /// formernas oförändrade beteende); satt = tvinga EXAKT den här
    /// pixelstorleken vid export, se `PlatformImage.resized(to:)` och
    /// `SearchViewModel.applyPipeline`.
    public let pixelSize: CGSize?

    public init(id: String, contour: OutputShape, aspectRatio: CGFloat?, pixelSize: CGSize?) {
        self.id = id
        self.contour = contour
        self.aspectRatio = aspectRatio
        self.pixelSize = pixelSize
    }

    public static func == (lhs: ShapePreset, rhs: ShapePreset) -> Bool { lhs.id == rhs.id }

    /// `String(localized:...)` UPPLÖST PER ANROP, inte en lagrad sträng -
    /// presets skapas EN gång som statiska konstanter, så en lagrad sträng
    /// skulle frysas till det språk som var aktivt vid appstart och aldrig
    /// följa med en språkväxling i Inställningar (se `CLAUDE.md`s
    /// lokaliseringsavsnitt, samma fälla som redan dokumenterad där).
    public var name: String {
        let locale = AppLanguage.current.locale
        switch id {
        case "linkedinProfile": return String(localized: "LinkedIn-profil", bundle: .module, locale: locale)
        case "avatarCircle": return String(localized: "Profilbild (cirkel)", bundle: .module, locale: locale)
        case "cvSquare": return String(localized: "CV-kvadrat", bundle: .module, locale: locale)
        case "instagramPost": return String(localized: "Instagram-inlägg", bundle: .module, locale: locale)
        case "instagramStory": return String(localized: "Instagram-story", bundle: .module, locale: locale)
        case "tiktok": return String(localized: "TikTok", bundle: .module, locale: locale)
        case "youtubeThumbnail": return String(localized: "YouTube-miniatyr", bundle: .module, locale: locale)
        default: return contour.label
        }
    }

    /// Den diskreta tekniska informationen under namnet i formväljaren -
    /// t.ex. "4:5 · 1080 × 1350". `nil` bara för Rektangel utan pixelmål
    /// (visar istället en egen text, se nedan) - övriga generiska former
    /// (alla 1:1) visar bara kvoten, utan pixelmått (de har inget fast).
    public var subtitle: String? {
        if let pixelSize {
            let ratio = Self.reducedRatioText(width: pixelSize.width, height: pixelSize.height)
            return "\(ratio) · \(Int(pixelSize.width)) × \(Int(pixelSize.height))"
        }
        guard let aspectRatio else {
            return String(localized: "Bildens egna proportioner", bundle: .module, locale: AppLanguage.current.locale)
        }
        return Self.reducedRatioText(width: aspectRatio, height: 1)
    }

    private static func reducedRatioText(width: CGFloat, height: CGFloat) -> String {
        let w = max(Int(width.rounded()), 1)
        let h = max(Int(height.rounded()), 1)
        let divisor = Self.gcd(w, h)
        return "\(w / divisor):\(h / divisor)"
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        b == 0 ? a : gcd(b, a % b)
    }

    /// Genererade programmatiskt från `OutputShape.allCases` - garanterar
    /// att de sex generiska formerna (Rektangel/Kvadrat/Avrundad kvadrat/
    /// Cirkel/Hexagon/Oktagon) förblir EXAKT oförändrade (samma kontur,
    /// samma namn, fri storlek härledd från källbilden) - inget dupliceras
    /// för hand.
    private static let genericPresets: [ShapePreset] = OutputShape.allCases.map { shape in
        ShapePreset(id: shape.rawValue, contour: shape, aspectRatio: shape == .rectangle ? nil : 1, pixelSize: nil)
    }

    /// De sju praktiska genvägarna - alla `.square`-kontur (vanlig
    /// rektangel, ingen extra formsiluett) UTOM "Profilbild (cirkel)".
    /// `aspectRatio` räknas alltid FRÅN `pixelSize` (aldrig en separat
    /// hårdkodad siffra) - kan inte hamna i otakt med den.
    public static let practicalPresets: [ShapePreset] = [
        practical(id: "linkedinProfile", contour: .square, pixelSize: CGSize(width: 800, height: 800)),
        practical(id: "avatarCircle", contour: .circle, pixelSize: CGSize(width: 800, height: 800)),
        practical(id: "cvSquare", contour: .square, pixelSize: CGSize(width: 1000, height: 1000)),
        practical(id: "instagramPost", contour: .square, pixelSize: CGSize(width: 1080, height: 1350)),
        practical(id: "instagramStory", contour: .square, pixelSize: CGSize(width: 1080, height: 1920)),
        practical(id: "tiktok", contour: .square, pixelSize: CGSize(width: 1080, height: 1920)),
        practical(id: "youtubeThumbnail", contour: .square, pixelSize: CGSize(width: 1280, height: 720)),
    ]

    private static func practical(id: String, contour: OutputShape, pixelSize: CGSize) -> ShapePreset {
        ShapePreset(id: id, contour: contour, aspectRatio: pixelSize.width / pixelSize.height, pixelSize: pixelSize)
    }

    /// Praktiska genvägar FÖRST (i den ordning de listas ovan), sedan de
    /// generiska geometriska formerna - visas i den ordningen i
    /// `ShapePickerView`s rutnät.
    public static let all: [ShapePreset] = practicalPresets + genericPresets

    /// Standardvalet - motsvarar dagens `OutputShape.square` (se
    /// `SearchViewModel.shapePreset`s dokumentation för varför kvadrat,
    /// inte rektangel, är default).
    public static let square = ShapePreset(id: OutputShape.square.rawValue, contour: .square, aspectRatio: 1, pixelSize: nil)
}
