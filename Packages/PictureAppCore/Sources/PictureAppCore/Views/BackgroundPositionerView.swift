import SwiftUI

/// Låter användaren panorera och zooma en egen bakgrundsbild innan den
/// tillämpas. `DragGesture`/`MagnificationGesture` är SwiftUIs inbyggda,
/// plattformsoberoende gester - samma kod hanterar både styrplatte-nyp på
/// Mac och fingernyp på iPhone/iPad, ingen plattformsspecifik gesthantering
/// behövs (till skillnad från t.ex. webb, där man måste hantera råa
/// pekar-event själv).
struct BackgroundPositionerView: View {
    let image: PlatformImage
    let previewAspectRatio: CGFloat
    let onDone: (CanvasTransform) -> Void
    let onCancel: () -> Void

    // Lagras som en ANDEL av förhandsvisningens bredd/höjd, precis som
    // `CanvasTransform.offset` - därför gäller samma värde oavsett om
    // slutbilden renderas i en helt annan upplösning än förhandsvisningen.
    @State private var committedOffsetFraction: CGSize
    @State private var committedScale: CGFloat
    @GestureState private var liveDrag: CGSize = .zero
    @GestureState private var liveMagnification: CGFloat = 1

    init(
        image: PlatformImage,
        previewAspectRatio: CGFloat,
        initialTransform: CanvasTransform,
        onDone: @escaping (CanvasTransform) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.image = image
        self.previewAspectRatio = previewAspectRatio
        self.onDone = onDone
        self.onCancel = onCancel
        _committedOffsetFraction = State(initialValue: initialTransform.offset)
        _committedScale = State(initialValue: max(initialTransform.scale, 1))
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Justera bakgrundsbilden")
                .font(.headline)
            Text("Dra för att flytta, nyp för att zooma.")
                .font(.caption)
                .foregroundStyle(.secondary)

            GeometryReader { geo in
                let containerSize = geo.size
                let scale = max(committedScale * liveMagnification, 1)
                let committedOffset = CGSize(
                    width: committedOffsetFraction.width * containerSize.width,
                    height: committedOffsetFraction.height * containerSize.height
                )
                let offset = CGSize(width: committedOffset.width + liveDrag.width, height: committedOffset.height + liveDrag.height)

                Image(platformImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: containerSize.width, height: containerSize.height)
                    .scaleEffect(scale)
                    .offset(offset)
                    .frame(width: containerSize.width, height: containerSize.height)
                    .clipped()
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture()
                            .updating($liveDrag) { value, state, _ in state = value.translation }
                            .onEnded { value in
                                let newOffset = CGSize(
                                    width: committedOffset.width + value.translation.width,
                                    height: committedOffset.height + value.translation.height
                                )
                                let clamped = Self.clampOffset(newOffset, scale: scale, containerSize: containerSize)
                                committedOffsetFraction = CGSize(
                                    width: clamped.width / containerSize.width,
                                    height: clamped.height / containerSize.height
                                )
                            }
                    )
                    .simultaneousGesture(
                        MagnificationGesture()
                            .updating($liveMagnification) { value, state, _ in state = value }
                            .onEnded { value in
                                committedScale = max(committedScale * value, 1)
                                let clamped = Self.clampOffset(committedOffset, scale: committedScale, containerSize: containerSize)
                                committedOffsetFraction = CGSize(
                                    width: clamped.width / containerSize.width,
                                    height: clamped.height / containerSize.height
                                )
                            }
                    )
            }
            .aspectRatio(previewAspectRatio, contentMode: .fit)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.3)))

            HStack {
                Button("Avbryt", role: .cancel) { onCancel() }
                Spacer()
                Button("Använd bakgrund") {
                    onDone(CanvasTransform(offset: committedOffsetFraction, scale: committedScale))
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 380, idealWidth: 460, minHeight: 460, idealHeight: 560)
    }

    /// Håller bilden täckande hela förhandsvisningen - samma regel som
    /// `BackgroundRemovalService.scaledToFill` tillämpar på slutbilden, så
    /// det man ser här är det man får.
    private static func clampOffset(_ offset: CGSize, scale: CGFloat, containerSize: CGSize) -> CGSize {
        let maxX = containerSize.width * (scale - 1) / 2
        let maxY = containerSize.height * (scale - 1) / 2
        return CGSize(
            width: min(max(offset.width, -maxX), maxX),
            height: min(max(offset.height, -maxY), maxY)
        )
    }
}
