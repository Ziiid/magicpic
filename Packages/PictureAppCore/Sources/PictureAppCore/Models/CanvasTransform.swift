import Foundation

/// Pan/zoom för en egen bakgrundsbild. `offset` är en ANDEL av
/// målytans bredd/höjd (inte punkter/pixlar), så samma transform ger
/// samma visuella placering oavsett om den tillämpas i en liten
/// förhandsvisning eller på slutbilden i full upplösning.
public struct CanvasTransform: Equatable {
    public var offset: CGSize
    public var scale: CGFloat

    public static let identity = CanvasTransform(offset: .zero, scale: 1)

    public init(offset: CGSize = .zero, scale: CGFloat = 1) {
        self.offset = offset
        self.scale = scale
    }
}
