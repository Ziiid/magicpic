import CoreGraphics
import Foundation

/// En användarritad, sluten kontur (formen "Frihand"). Punkterna är
/// NORMALISERADE (0...1) mot kanvasen/bilden de ritades på, så samma kontur
/// kan läggas på vilken storlek som helst - förhandsvisning, miniatyr och
/// export ger då alltid samma form (samma princip som `OutputShape.cgPath`).
public struct FreeformPath: Equatable {
    public let points: [CGPoint]

    public init(points: [CGPoint]) {
        self.points = points
    }

    /// Minst tre punkter krävs för en yta.
    public var isUsable: Bool { points.count >= 3 }

    /// Jämnad kontur (kvadratiska kurvor genom mittpunkterna mellan
    /// punkterna) inskriven i `rect` - en rå handritad polylinje blir
    /// kantig.
    public func cgPath(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        guard points.count >= 3 else {
            path.addRect(rect)
            return path
        }
        let mapped = points.map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height) }
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        path.move(to: mid(mapped[mapped.count - 1], mapped[0]))
        for i in 0..<mapped.count {
            let next = mapped[(i + 1) % mapped.count]
            path.addQuadCurve(to: mid(mapped[i], next), control: mapped[i])
        }
        path.closeSubpath()
        return path
    }
}
