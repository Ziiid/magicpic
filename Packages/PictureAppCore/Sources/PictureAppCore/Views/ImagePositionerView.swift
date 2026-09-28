import SwiftUI

/// Dialog för att panorera, zooma och rotera en bild inom en målyta - just
/// nu bara använd för att positionera en egen bakgrundsbild. Motivets
/// formramning sker numera direkt i `DetailPanel` (se
/// `SubjectFramingCanvas`), inte via en dialog. Själva dra/nyp/vrid-
/// hanteringen sitter i den delade `ManipulableImageView`.
struct ImagePositionerView: View {
    // `String`, redan LOKALISERAD av anropsstället (via `L(...)`) - INTE
    // `LocalizedStringKey`. Provade `LocalizedStringKey` här tidigare i tron
    // att SwiftUI då skulle slå upp den mot rätt bundle automatiskt, men det
    // stämmer INTE - `Text(_:LocalizedStringKey)`/`Button(_:LocalizedStringKey:)`
    // utan uttrycklig `bundle:` letar i `Bundle.main` precis som `String`-
    // varianten, och `Button` exponerar dessutom ingen `bundle:`-parameter
    // alls att sätta här. Enda robusta sättet: lös upp texten till en
    // FÄRDIG `String` VID ANROPSSTÄLLET (`L(...)`) och skicka den vidare -
    // se `CLAUDE.md`s lokaliseringsavsnitt.
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
        // `CanvasTransform.minScale`, inte `1` - annars skulle att öppna
        // positioneraren igen för en bild man redan medvetet gjort mindre
        // än kanvasen (se `allowsExposedEdges`/`ManipulableImageView`)
        // tvinga tillbaka den till cover-storlek bara av att öppna dialogen.
        _transform = State(initialValue: CanvasTransform(
            offset: initialTransform.offset,
            scale: max(initialTransform.scale, CanvasTransform.minScale),
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

            ManipulableImageView(image: image, clipShape: clipShape, transform: $transform, allowsExposedEdges: true)
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
                        set: { transform.scale = max($0, CanvasTransform.minScale) }
                    ), in: CanvasTransform.minScale...6)
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
                Button(L("Avbryt"), role: .cancel) { onCancel() }
                Spacer()
                Button(doneLabel) { onDone(transform) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 380, idealWidth: 460, minHeight: 520, idealHeight: 640)
    }
}
