import CoreGraphics
import Foundation
import SwiftUI

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

    /// Konturen formen beskär till, inskriven i `rect`. Delas mellan
    /// `ShapeCropService` (den faktiska beskärningen) och `ImagePositionerView`
    /// (förhandsvisningen vid positionering) så de alltid stämmer överens.
    public func cgPath(in rect: CGRect) -> CGPath {
        switch self {
        case .rectangle, .square:
            return CGPath(rect: rect, transform: nil)
        case .roundedSquare:
            let corner = rect.width * 0.18
            return CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
        case .circle:
            return CGPath(ellipseIn: rect, transform: nil)
        case .hexagon:
            return Self.regularPolygonPath(sides: 6, in: rect)
        case .octagon:
            return Self.regularPolygonPath(sides: 8, in: rect)
        }
    }

    /// SwiftUI-form som motsvarar `cgPath(in:)`, för att kunna klippa/rama in
    /// förhandsvisningen i `ImagePositionerView` med exakt samma kontur som
    /// slutresultatet.
    public var swiftUIShape: AnyShape {
        AnyShape(OutputShapeContour(shape: self))
    }

    /// En regelbunden N-hörning inskriven i `rect`, roterad så den alltid
    /// får en platt sida längst upp och ner (t.ex. en "stopptecken"-oktagon)
    /// istället för en spets.
    private static func regularPolygonPath(sides: Int, in rect: CGRect) -> CGPath {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let angleOffset = -CGFloat.pi / 2 + (.pi / CGFloat(sides))

        let path = CGMutablePath()
        for i in 0..<sides {
            let angle = angleOffset + (2 * .pi * CGFloat(i) / CGFloat(sides))
            let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

private struct OutputShapeContour: Shape {
    let shape: OutputShape
    func path(in rect: CGRect) -> Path {
        Path(shape.cgPath(in: rect))
    }
}
