import SwiftUI

/// En logotyp/bild som ligger ovanpå bilden (ovanpå motiv och bakgrund,
/// under en ev. text, före formens siluett). Precis som `TextOverlay` är allt
/// geometriskt RELATIVT till kanvasen, så förhandsvisningen
/// (`LogoOverlayLayer`) och exporten (`LogoOverlayService`) hamnar på samma
/// ställe oavsett upplösning.
public struct LogoOverlay: Equatable {
    public var image: PlatformImage
    /// Logotypens BREDD som andel av kanvasens bredd - höjden följer bildens
    /// eget bildförhållande.
    public var size: CGFloat
    /// Mittpunktens förskjutning från kanvasens mitt, som andel av kanvasens
    /// bredd/höjd (positivt Y = nedåt).
    public var offset: CGSize
    public var rotation: Angle
    /// Spegelvänd horisontellt (efter rotationen, runt egen mitt).
    public var isFlipped: Bool

    public static let minSize: CGFloat = 0.05
    public static let maxSize: CGFloat = 1.5

    public init(image: PlatformImage, size: CGFloat = 0.25, offset: CGSize = .zero, rotation: Angle = .zero, isFlipped: Bool = false) {
        self.image = image
        self.size = size
        self.offset = offset
        self.rotation = rotation
        self.isFlipped = isFlipped
    }

    // `PlatformImage` (NSImage/UIImage) är inte `Equatable` på värde -
    // jämför instansen, samma som `BackgroundOption.custom`.
    public static func == (lhs: LogoOverlay, rhs: LogoOverlay) -> Bool {
        lhs.image === rhs.image
            && lhs.size == rhs.size
            && lhs.offset == rhs.offset
            && lhs.rotation == rhs.rotation
            && lhs.isFlipped == rhs.isFlipped
    }
}
