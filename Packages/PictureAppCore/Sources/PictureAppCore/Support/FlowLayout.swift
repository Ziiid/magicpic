import SwiftUI

/// Enkel "flow"-layout: lägger ut sina barn i rader i sin egna naturliga
/// (inte utsträckta) storlek, och radbryter automatiskt till nästa rad så
/// fort ett barn inte får plats på den nuvarande bredden - till skillnad
/// från en `LazyVGrid` (som tvingar alla celler till samma kolumnbredd, och
/// gör smala/breda knappar lika breda) ser resultatet ut som en vanlig,
/// tätt packad verktygsrad oavsett hur många rader den råkar behöva.
///
/// Används av `DetailPanel`s knapprad, som tidigare låg i en horisontellt
/// scrollande `HStack` - på en smal skärm (iPhone, eller Macs 380pt-panel
/// när många verktyg lagts till) svämmade den över den synliga bredden utan
/// någon tydlig visuell antydan om att man kunde scrolla för att se resten
/// (rapporterat 2026-09-26).
struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidths: [CGFloat] = [0]
        var rowHeights: [CGFloat] = [0]

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let currentRow = rowWidths.count - 1
            if rowWidths[currentRow] > 0, rowWidths[currentRow] + horizontalSpacing + size.width > maxWidth {
                rowWidths.append(0)
                rowHeights.append(0)
            }
            let row = rowWidths.count - 1
            rowWidths[row] += (rowWidths[row] > 0 ? horizontalSpacing : 0) + size.width
            rowHeights[row] = max(rowHeights[row], size.height)
        }

        let width = rowWidths.max() ?? 0
        let height = rowHeights.reduce(0, +) + verticalSpacing * CGFloat(max(0, rowHeights.count - 1))
        return CGSize(width: min(width, maxWidth), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.minX + bounds.width {
                x = bounds.minX
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }
    }

    func makeCache(subviews: Subviews) {}
}
