import CoreGraphics
import Foundation
import SwiftUI

/// En färdig tvåfärgad bakgrundsgradient. Riktningen är en vinkel (grader,
/// 0 = vänster→höger, 90 = uppifrån→ner, SwiftUIs skärmkoordinater) och
/// start-/slutpunkten räknas som ENHETSKOORDINATER i kanvasen
/// (`startPoint`/`endPoint`) - EXAKT samma värden används av
/// förhandsvisningen (`LinearGradient`) och exporten
/// (`BackgroundRemovalService`, `CILinearGradient`), så de ger samma bild.
public struct GradientPreset: Identifiable, Equatable {
    public let id: String
    // sRGB 0...1
    let start: (r: Double, g: Double, b: Double)
    let end: (r: Double, g: Double, b: Double)
    public let angleDegrees: Double

    init(id: String, start: UInt32, end: UInt32, angleDegrees: Double = 45) {
        self.id = id
        self.start = Self.components(start)
        self.end = Self.components(end)
        self.angleDegrees = angleDegrees
    }

    public static func == (lhs: GradientPreset, rhs: GradientPreset) -> Bool { lhs.id == rhs.id }

    private static func components(_ hex: UInt32) -> (Double, Double, Double) {
        (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }

    public var startColor: Color { Color(.sRGB, red: start.r, green: start.g, blue: start.b, opacity: 1) }
    public var endColor: Color { Color(.sRGB, red: end.r, green: end.g, blue: end.b, opacity: 1) }

    var startCGColor: CGColor { CGColor(srgbRed: start.r, green: start.g, blue: start.b, alpha: 1) }
    var endCGColor: CGColor { CGColor(srgbRed: end.r, green: end.g, blue: end.b, alpha: 1) }

    /// Start-/slutpunkt i enhetskoordinater (0...1, y nedåt som i SwiftUI).
    public var startUnitPoint: CGPoint {
        let a = angleDegrees * .pi / 180
        return CGPoint(x: 0.5 - 0.5 * cos(a), y: 0.5 - 0.5 * sin(a))
    }

    public var endUnitPoint: CGPoint {
        let a = angleDegrees * .pi / 180
        return CGPoint(x: 0.5 + 0.5 * cos(a), y: 0.5 + 0.5 * sin(a))
    }

    public var linearGradient: LinearGradient {
        LinearGradient(
            colors: [startColor, endColor],
            startPoint: UnitPoint(x: startUnitPoint.x, y: startUnitPoint.y),
            endPoint: UnitPoint(x: endUnitPoint.x, y: endUnitPoint.y)
        )
    }

    public static let all: [GradientPreset] = [
        GradientPreset(id: "sunset", start: 0xFF9966, end: 0xFF5E62),
        GradientPreset(id: "fire", start: 0xF5AF19, end: 0xF12711),
        GradientPreset(id: "peach", start: 0xFFECD2, end: 0xFCB69F),
        GradientPreset(id: "rose", start: 0xFFDDE1, end: 0xEE9CA7),
        GradientPreset(id: "berry", start: 0x8E2DE2, end: 0x4A00E0),
        GradientPreset(id: "lavender", start: 0xCC95C0, end: 0x7AA1D2),
        GradientPreset(id: "ocean", start: 0x6DD5ED, end: 0x2193B0),
        GradientPreset(id: "sky", start: 0xC2E9FB, end: 0xA1C4FD),
        GradientPreset(id: "mint", start: 0x38EF7D, end: 0x11998E),
        GradientPreset(id: "midnight", start: 0x414345, end: 0x232526),
    ]
}
