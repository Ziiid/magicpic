import SwiftUI

/// Dialog för att panorera, zooma och rotera en bild inom en målyta - just
/// nu bara använd för att positionera en egen bakgrundsbild. Motivets
/// formramning sker numera direkt i `DetailPanel` (se
/// `SubjectFramingCanvas`), inte via en dialog. Själva dra/nyp/vrid-
/// hanteringen sitter i den delade `ManipulableImageView`.
struct ImagePositionerView: View {
    let title: String
    let subtitle: String
    let image: PlatformImage
    let previewAspectRatio: CGFloat
    let clipShape: AnyShape
    let doneLabel: String
    let onDone: (CanvasTransform) -> Void
    let onCancel: () -> Void

    @State private var transform: CanvasTransform

    init(
        title: String,
        subtitle: String,
        image: PlatformImage,
        previewAspectRatio: CGFloat,
        clipShape: AnyShape,
        doneLabel: String,
        initialTransform: CanvasTransform,
        onDone: @escaping (CanvasTransform) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.image = image
        self.previewAspectRatio = previewAspectRatio
        self.clipShape = clipShape
        self.doneLabel = doneLabel
        self.onDone = onDone
        self.onCancel = onCancel
        _transform = State(initialValue: CanvasTransform(
            offset: initialTransform.offset,
            scale: max(initialTransform.scale, 1),
            rotation: initialTransform.rotation
        ))
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            ManipulableImageView(image: image, clipShape: clipShape, transform: $transform)
                .aspectRatio(previewAspectRatio, contentMode: .fit)
                .background(CheckerboardBackground())
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.3)))

            // Skjutreglage som reserv om nyp-/rotationsgesten av någon
            // anledning inte känns igen på användarens enhet.
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "minus.magnifyingglass").foregroundStyle(.secondary)
                    Slider(value: Binding(
                        get: { transform.scale },
                        set: { transform.scale = max($0, 1) }
                    ), in: 1...6)
                    Image(systemName: "plus.magnifyingglass").foregroundStyle(.secondary)
                }
                HStack {
                    Image(systemName: "rotate.left").foregroundStyle(.secondary)
                    Slider(value: Binding(
                        get: { transform.rotation.degrees },
                        set: { transform.rotation = .degrees($0) }
                    ), in: -180...180)
                    Image(systemName: "rotate.right").foregroundStyle(.secondary)
                }
            }

            HStack {
                Button("Avbryt", role: .cancel) { onCancel() }
                Spacer()
                Button(doneLabel) { onDone(transform) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 380, idealWidth: 460, minHeight: 520, idealHeight: 640)
    }
}
