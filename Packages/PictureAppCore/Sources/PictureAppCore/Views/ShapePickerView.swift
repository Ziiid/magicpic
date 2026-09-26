import SwiftUI

/// Formväljare med RIKTIGA förhandsgranskningar (bilden faktiskt beskuren
/// till varje form) - samma mönster som `PhotoFilterPickerView`, tidigare
/// saknat här (formvalet var bara en textmeny med en generisk ikon per
/// form, rapporterat 2026-09-26).
///
/// Miniatyrerna genereras EN gång från en nedskalad kopia av bilden
/// (`PlatformImage.resized(maxDimension:)`) - till skillnad från
/// `BackgroundStylePickerView` finns ingen mask att hålla i synk med, så
/// nedskalning FÖRE beskärning är säkert här (`ShapeCropService` skapar
/// sin egen formmask i exakt den storlek den beskurna bilden råkar ha).
struct ShapePickerView: View {
    let baseImage: PlatformImage
    let transform: CanvasTransform
    let currentShape: OutputShape
    let onSelect: (OutputShape) -> Void
    let onDone: () -> Void

    @State private var thumbnails: [OutputShape: PlatformImage] = [:]

    var body: some View {
        VStack(spacing: 16) {
            Text("Form")
                .font(.headline)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 12)], spacing: 16) {
                    ForEach(OutputShape.allCases) { shape in
                        Button {
                            onSelect(shape)
                        } label: {
                            VStack(spacing: 6) {
                                thumbnailView(for: shape)
                                    .frame(width: 68, height: 68)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .strokeBorder(shape == currentShape ? AppTheme.accent : Color.secondary.opacity(0.2), lineWidth: shape == currentShape ? 3 : 1)
                                    )
                                Text(shape.label)
                                    .font(.caption2)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
            }

            HStack {
                Spacer()
                Button("Klart") { onDone() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 340, idealWidth: 420, minHeight: 420, idealHeight: 480)
        .task { await generateThumbnails() }
    }

    @ViewBuilder
    private func thumbnailView(for shape: OutputShape) -> some View {
        if let thumbnail = thumbnails[shape] {
            ZStack {
                CheckerboardBackground()
                Image(platformImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        } else {
            Rectangle()
                .fill(Color.secondary.opacity(0.15))
                .overlay(ProgressView().controlSize(.small))
        }
    }

    private func generateThumbnails() async {
        let shapeCrop = ShapeCropService()
        let small = baseImage.resized(maxDimension: 160)
        for shape in OutputShape.allCases {
            guard let result = try? shapeCrop.apply(shape, to: small, transform: transform) else { continue }
            thumbnails[shape] = result
        }
    }
}
