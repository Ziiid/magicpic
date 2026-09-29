import SwiftUI

/// Teckensnitten användaren kan välja för en text på bilden. Bara
/// teckensnitt som finns på BÅDA plattformarna (macOS och iOS) - namnen är
/// PostScript-namn, som både SwiftUI (`Font.custom`) och CoreText
/// (`CTFontCreateWithName`, används vid export) förstår.
public enum TextFontStyle: String, CaseIterable, Identifiable {
    case modern
    case heavy
    case serif
    case handwritten
    case mono

    public var id: String { rawValue }

    public var postScriptName: String {
        switch self {
        case .modern: return "HelveticaNeue-Bold"
        case .heavy: return "AvenirNext-Heavy"
        case .serif: return "Georgia-Bold"
        case .handwritten: return "MarkerFelt-Wide"
        case .mono: return "Menlo-Bold"
        }
    }

    public var label: String {
        switch self {
        case .modern: return L("Modern")
        case .heavy: return L("Kraftig")
        case .serif: return L("Serif")
        case .handwritten: return L("Handskrift")
        case .mono: return L("Mono")
        }
    }
}

/// En text som ligger ovanpå bilden (ovanpå motiv och bakgrund, före
/// formens siluett - så den klipps av t.ex. en cirkel precis som resten).
/// Allt geometriskt är RELATIVT till kanvasen, inte punkter/pixlar, så
/// förhandsvisningen (`TextOverlayLayer`) och exporten
/// (`TextOverlayService`) hamnar på samma ställe oavsett upplösning -
/// samma princip som `CanvasTransform.offset`.
public struct TextOverlay: Equatable {
    public var text: String
    public var fontStyle: TextFontStyle
    public var color: Color
    /// Teckenstorlek som andel av kanvasens BREDD.
    public var size: CGFloat
    /// Textens mittpunkt, förskjuten från kanvasens mitt som andel av
    /// kanvasens bredd/höjd (positivt Y = nedåt, som i SwiftUI).
    public var offset: CGSize
    public var rotation: Angle
    public var hasShadow: Bool

    public static let minSize: CGFloat = 0.03
    public static let maxSize: CGFloat = 0.6

    public init(
        text: String,
        fontStyle: TextFontStyle = .heavy,
        color: Color = .white,
        size: CGFloat = 0.1,
        offset: CGSize = .zero,
        rotation: Angle = .zero,
        hasShadow: Bool = true
    ) {
        self.text = text
        self.fontStyle = fontStyle
        self.color = color
        self.size = size
        self.offset = offset
        self.rotation = rotation
        self.hasShadow = hasShadow
    }

    public var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
