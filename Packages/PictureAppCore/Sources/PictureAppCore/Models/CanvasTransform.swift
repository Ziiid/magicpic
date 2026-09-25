import CoreImage
import Foundation
import SwiftUI

/// Pan/zoom/rotation för en bild inom en målyta - en egen bakgrundsbild
/// eller motivet inom formbeskärningens kvadrat. `offset` är en ANDEL av
/// målytans bredd/höjd (inte punkter/pixlar), så samma transform ger
/// samma visuella placering oavsett om den tillämpas i en liten
/// förhandsvisning eller på slutbilden i full upplösning.
public struct CanvasTransform: Equatable {
    public var offset: CGSize
    public var scale: CGFloat
    public var rotation: Angle

    public static let identity = CanvasTransform(offset: .zero, scale: 1, rotation: .zero)

    public init(offset: CGSize = .zero, scale: CGFloat = 1, rotation: Angle = .zero) {
        self.offset = offset
        self.scale = scale
        self.rotation = rotation
    }

    /// Roterar, skalar och beskär `image` så den täcker `target` helt
    /// (aspect fill), justerad med denna pan/zoom/rotation. Rotationen
    /// tillämpas runt bildens eget centrum FÖRE skalningen, som räknas mot
    /// den roterade bildens (större) begränsningsruta - annars skulle en
    /// roterad bild kunna lämna tomma hörn. `scale` klampas till minst 1 -
    /// att zooma UT under "cover"-nivån skulle blotta kanter utan
    /// bildinnehåll. Beskärningsfönstret klampas i sin tur till att alltid
    /// ligga innanför den skalade bilden, så en panorering aldrig kan dra
    /// fram tomma kanter (även om transformen råkar ange ett värde utanför
    /// giltigt intervall). Delad av `BackgroundRemovalService` (egen
    /// bakgrundsbild) och `ShapeCropService` (motivets placering i formen)
    /// så de beter sig identiskt.
    public func scaledToFill(_ image: CIImage, target: CGRect) -> CIImage {
        let rotated: CIImage
        if rotation == .zero {
            rotated = image
        } else {
            let center = CGPoint(x: image.extent.midX, y: image.extent.midY)
            rotated = image
                .transformed(by: CGAffineTransform(translationX: -center.x, y: -center.y))
                .transformed(by: CGAffineTransform(rotationAngle: CGFloat(rotation.radians)))
        }

        let baseScale = max(target.width / rotated.extent.width, target.height / rotated.extent.height)
        let effectiveScale = baseScale * max(scale, 1)
        let scaled = rotated.transformed(by: CGAffineTransform(scaleX: effectiveScale, y: effectiveScale))

        let centeredX = (scaled.extent.width - target.width) / 2
        let centeredY = (scaled.extent.height - target.height) / 2
        // `offset` är en andel av målytan; CoreImages y-axel pekar uppåt,
        // SwiftUIs nedåt, därav minustecknet på Y.
        let panX = offset.width * target.width
        let panY = -offset.height * target.height

        let maxX = max(scaled.extent.width - target.width, 0)
        let maxY = max(scaled.extent.height - target.height, 0)
        let cropX = min(max(centeredX - panX, 0), maxX)
        let cropY = min(max(centeredY - panY, 0), maxY)

        let cropOrigin = CGPoint(x: scaled.extent.minX + cropX, y: scaled.extent.minY + cropY)
        let cropped = scaled.cropped(to: CGRect(origin: cropOrigin, size: target.size))
        return cropped.transformed(by: CGAffineTransform(translationX: target.minX - cropOrigin.x, y: target.minY - cropOrigin.y))
    }

    /// Håller ett pan-offset (i punkter, för en förhandsvisning av given
    /// storlek) inom vad som faktiskt täcker `containerSize` vid `scale` -
    /// samma "cover"-regel som `scaledToFill` tillämpar på slutbilden, så
    /// det man ser i positioneraren är det man får. Delad av
    /// `ManipulableImageView`, som används både för bakgrunds- och
    /// formpositionering.
    ///
    /// Måste räkna med `imageSize`s EGEN bildproportion, inte bara `scale` -
    /// annars underskattas hur mycket bilden faktiskt "svämmar över"
    /// `containerSize` redan innan användaren zoomat alls (t.ex. en stående
    /// bild i en kvadratisk ram fyller ut höjden mer än bredden vid
    /// scale=1). Med den gamla formeln (bara `containerSize * (scale-1)/2`)
    /// gick det att panorera längre under själva draget (som visar den
    /// faktiska, oklampade positionen) än vad gränsen sedan tillät vid
    /// släpp - bilden "hoppade" tillbaka mot mitten istället för att stanna
    /// där man släppte den (upptäckt när man ville visa absolut övre
    /// kanten på en stående bild).
    public static func clampedOffset(_ offset: CGSize, scale: CGFloat, imageSize: CGSize, containerSize: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0, containerSize.width > 0, containerSize.height > 0 else {
            return .zero
        }

        let containerAspect = containerSize.width / containerSize.height
        let imageAspect = imageSize.width / imageSize.height
        // Bildens renderade storlek vid scale=1 (innan användarens zoom),
        // efter att `.aspectRatio(contentMode: .fill)` täckt containern -
        // samma "cover"-beräkning som `scaledToFill`, fast i punkter för
        // förhandsvisningen istället för pixlar för slutbilden.
        let coveredSize: CGSize = imageAspect > containerAspect
            ? CGSize(width: containerSize.height * imageAspect, height: containerSize.height)
            : CGSize(width: containerSize.width, height: containerSize.width / imageAspect)

        let totalWidth = coveredSize.width * scale
        let totalHeight = coveredSize.height * scale
        let maxX = max((totalWidth - containerSize.width) / 2, 0)
        let maxY = max((totalHeight - containerSize.height) / 2, 0)
        return CGSize(
            width: min(max(offset.width, -maxX), maxX),
            height: min(max(offset.height, -maxY), maxY)
        )
    }
}
