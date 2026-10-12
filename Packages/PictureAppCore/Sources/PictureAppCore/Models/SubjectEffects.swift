import SwiftUI

/// Effekter som läggs på motivets urklipp (INNAN det positioneras och
/// läggs över bakgrunden): en mjuk skugga och/eller en kontur
/// ("klistermärkeskant"). Båda är relativa till bildens storlek (andel av
/// längsta sidan), så de skalar med bilden oavsett upplösning - och bakas
/// in i själva urklippet (`SubjectEffectService`), så förhandsvisning och
/// export är identiska och följer med motivets pan/zoom/rotation/spegling.
public struct SubjectEffects: Equatable {
    /// 0...1, 0 = ingen skugga.
    public var shadow: Double
    /// 0...1, 0 = ingen kontur.
    public var outlineWidth: Double
    public var outlineColor: Color

    public static let none = SubjectEffects()

    public init(shadow: Double = 0, outlineWidth: Double = 0, outlineColor: Color = .white) {
        self.shadow = shadow
        self.outlineWidth = outlineWidth
        self.outlineColor = outlineColor
    }

    public var isNone: Bool { shadow <= 0 && outlineWidth <= 0 }
}
