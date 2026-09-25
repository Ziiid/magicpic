import SwiftUI

/// Kärnan i dra/nyp/vrid-hanteringen för en bild inom en given kontur -
/// delad mellan den inbäddade formramningen i `DetailPanel` (verksam direkt
/// när en bild laddats in, se `SubjectFramingCanvas`) och
/// `ImagePositionerView` (bakgrundsbildens positioneringsdialog).
///
/// `DragGesture`/`MagnifyGesture`/`RotateGesture` slås ihop till EN
/// sammansatt gest med `.simultaneously(with:)` och sätts med ETT enda
/// `.gesture(...)`-anrop - separata `.gesture`/`.simultaneousGesture`-anrop
/// (det tidigare mönstret) levererade inte nyp-/rotationshändelser
/// pålitligt i praktiken. `transform` är en bindning så anroparen (dialogen
/// respektive den inbäddade ramningsytan) alltid har det committade värdet
/// utan att behöva duplicera commit-logik.
struct ManipulableImageView: View {
    let image: PlatformImage
    let clipShape: AnyShape
    @Binding var transform: CanvasTransform
    var onCommit: () -> Void = {}

    @GestureState private var liveDrag: CGSize = .zero
    @GestureState private var liveMagnification: CGFloat = 1
    @GestureState private var liveRotation: Angle = .zero

    var body: some View {
        GeometryReader { geo in
            let containerSize = geo.size
            let scale = max(transform.scale * liveMagnification, 1)
            let rotation = transform.rotation + liveRotation
            let committedOffset = CGSize(
                width: transform.offset.width * containerSize.width,
                height: transform.offset.height * containerSize.height
            )
            let offset = CGSize(width: committedOffset.width + liveDrag.width, height: committedOffset.height + liveDrag.height)

            Image(platformImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: containerSize.width, height: containerSize.height)
                .rotationEffect(rotation)
                .scaleEffect(scale)
                .offset(offset)
                .frame(width: containerSize.width, height: containerSize.height)
                .clipShape(clipShape)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .updating($liveDrag) { value, state, _ in state = value.translation }
                        .onEnded { value in
                            let newOffset = CGSize(
                                width: committedOffset.width + value.translation.width,
                                height: committedOffset.height + value.translation.height
                            )
                            let clamped = CanvasTransform.clampedOffset(newOffset, scale: scale, imageSize: image.size, containerSize: containerSize)
                            transform.offset = CGSize(
                                width: clamped.width / containerSize.width,
                                height: clamped.height / containerSize.height
                            )
                            onCommit()
                        }
                        .simultaneously(with:
                            MagnifyGesture()
                                .updating($liveMagnification) { value, state, _ in state = value.magnification }
                                .onEnded { value in
                                    transform.scale = max(transform.scale * value.magnification, 1)
                                    let clamped = CanvasTransform.clampedOffset(committedOffset, scale: transform.scale, imageSize: image.size, containerSize: containerSize)
                                    transform.offset = CGSize(
                                        width: clamped.width / containerSize.width,
                                        height: clamped.height / containerSize.height
                                    )
                                    onCommit()
                                }
                        )
                        .simultaneously(with:
                            RotateGesture()
                                .updating($liveRotation) { value, state, _ in state = value.rotation }
                                .onEnded { value in
                                    transform.rotation += value.rotation
                                    onCommit()
                                }
                        )
                )
                .overlay(clipShape.stroke(Color.white.opacity(0.8), lineWidth: 2))
        }
    }
}
