import SwiftUI

/// Ritar en egen kontur ("Frihand") ovanpå bilden: dra med musen/fingret
/// runt det som ska behållas, släpp, och tryck Klart. Punkterna sparas
/// normaliserade mot BILDENS yta (se `FreeformPath`), så konturen ger samma
/// form i förhandsvisning, miniatyr och export. Allt utanför konturen
/// mörkas medan man ritar.
struct FreeformDrawView: View {
    let baseImage: PlatformImage
    let onDone: (FreeformPath) -> Void
    let onCancel: () -> Void

    @State private var points: [CGPoint] = []

    private var path: FreeformPath { FreeformPath(points: points) }

    var body: some View {
        VStack(spacing: 10) {
            Text(L("Rita en egen form"))
                .font(.headline)
            Text(L("Dra runt det du vill behålla. Släpp för att stänga formen."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            GeometryReader { geo in
                let imageRect = Self.fitRect(for: baseImage.size, in: geo.size)
                ZStack {
                    CheckerboardBackground()
                    Image(platformImage: baseImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geo.size.width, height: geo.size.height)

                    // Mörkar allt utanför konturen (even-odd), och ritar
                    // själva konturen som en grön linje.
                    if points.count >= 2 {
                        Path { p in
                            p.addRect(imageRect)
                            p.addPath(Path(path.cgPath(in: imageRect)))
                        }
                        .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
                        .allowsHitTesting(false)

                        Path(path.cgPath(in: imageRect))
                            .stroke(AppTheme.accent, lineWidth: 2)
                            .allowsHitTesting(false)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let x = (value.location.x - imageRect.minX) / imageRect.width
                            let y = (value.location.y - imageRect.minY) / imageRect.height
                            let point = CGPoint(x: min(max(x, 0), 1), y: min(max(y, 0), 1))
                            // Ny teckning börjar tomt: första punkten i ett
                            // nytt drag rensar den gamla.
                            if value.translation == .zero { points = [] }
                            // Hoppa över punkter nära den förra - färre,
                            // jämnare punkter.
                            if let last = points.last,
                               hypot((point.x - last.x) * imageRect.width, (point.y - last.y) * imageRect.height) < 4 {
                                return
                            }
                            points.append(point)
                        }
                )
            }
            .background(Color.black.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 16) {
                Button(L("Avbryt"), role: .cancel) { onCancel() }
                    .frame(minWidth: 80)
                Button(L("Rensa")) { points = [] }
                    .frame(minWidth: 80)
                    .disabled(points.isEmpty)
                Button(L("Klart")) { onDone(path) }
                    .keyboardShortcut(.defaultAction)
                    .frame(minWidth: 80)
                    .disabled(!path.isUsable)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(16)
        .frame(minWidth: 520, idealWidth: 760, maxWidth: .infinity, minHeight: 520, idealHeight: 760, maxHeight: .infinity)
    }

    /// Bildens faktiska yta inuti `container` med `.fit`.
    private static func fitRect(for contentSize: CGSize, in container: CGSize) -> CGRect {
        guard contentSize.width > 0, contentSize.height > 0 else { return CGRect(origin: .zero, size: container) }
        let scale = min(container.width / contentSize.width, container.height / contentSize.height)
        let size = CGSize(width: contentSize.width * scale, height: contentSize.height * scale)
        return CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }
}
