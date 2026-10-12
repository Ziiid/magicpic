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
    /// Speglad horisontellt (runt bildens egen mitt, FÖRE rotationen).
    public var isMirrored: Bool

    public static let identity = CanvasTransform(offset: .zero, scale: 1, rotation: .zero)

    /// Lägsta tillåtna `scale` (som andel av "cover"-skalan, `1` = precis
    /// täcker kanvasen) när `allowsExposedEdges` är satt - annars skulle
    /// bilden kunna zoomas bort till praktiskt taget osynlig/omöjlig att
    /// träffa med en gest. ~15% av cover-storleken lämnar gott om utrymme
    /// att medvetet göra bilden mindre än kanvasen (se `buggs.md`) utan den
    /// risken. EN enda konstant, återanvänd av `ManipulableImageView`
    /// (live-förhandsvisningen) OCH `scaledToFill` (slutrenderingen), så de
    /// aldrig kan hamna i otakt med varandra.
    public static let minScale: CGFloat = 0.15

    public init(offset: CGSize = .zero, scale: CGFloat = 1, rotation: Angle = .zero, isMirrored: Bool = false) {
        self.offset = offset
        self.scale = scale
        self.rotation = rotation
        self.isMirrored = isMirrored
    }

    /// Roterar, skalar och beskär `image` mot `target`, justerad med denna
    /// pan/zoom/rotation. Rotationen tillämpas runt bildens eget centrum
    /// FÖRE skalningen, som räknas mot den roterade bildens (större)
    /// begränsningsruta - annars skulle en roterad bild kunna lämna tomma
    /// hörn. Delad av `BackgroundRemovalService` (egen bakgrundsbild) och
    /// `ShapeCropService` (motivets placering i formen) så de beter sig
    /// identiskt.
    ///
    /// - Parameter allowsExposedEdges: Om sant hoppas den annars ovillkorade
    ///   "cover"-klampningen över på TVÅ sätt: `scale` tillåts gå ner till
    ///   `CanvasTransform.minScale` (inte bara ner till `1`, "precis
    ///   täcker") och beskärningsfönstret klampas inte längre till att
    ///   ligga innanför den skalade bilden - en användare kan alltså
    ///   medvetet göra bilden MINDRE än kanvasen och/eller panorera så en
    ///   kant av `target` blottas. `CIImage` returnerar genomskinliga
    ///   pixlar för koordinater utanför sin egen `extent` (samma beteende
    ///   som redan noterat för `CIGaussianBlur` i
    ///   `BackgroundRemovalService.makeBackgroundImage`), så resultatet blir
    ///   automatiskt genomskinligt där bilden inte når fram - ingen extra
    ///   kompositering behövs. Satt av BÅDA anropsställena idag
    ///   (`BackgroundRemovalService`s egna bakgrundsbild och
    ///   `ShapeCropService` - se dess dokumentation för varför ingen av dem
    ///   riskerar "hål" i själva motivurklippet trots det, de beskär en
    ///   REDAN kompositerad bild, inte Visions mask). `false` är bara kvar
    ///   som ett säkert default ("alltid full täckning") om metoden
    ///   återanvänds någon annanstans senare utan att uttryckligen ta
    ///   ställning.
    public func scaledToFill(_ image: CIImage, target: CGRect, allowsExposedEdges: Bool = false) -> CIImage {
        // Spegling FÖRST (inom bildens egen extent), sedan rotation - samma
        // ordning som `ManipulableImageView` (scaleEffect(x:-1) före
        // rotationEffect).
        let source: CIImage = isMirrored
            ? image.transformed(by: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: image.extent.minX + image.extent.maxX, ty: 0))
            : image
        let rotated: CIImage
        if rotation == .zero {
            rotated = source
        } else {
            let center = CGPoint(x: source.extent.midX, y: source.extent.midY)
            rotated = source
                .transformed(by: CGAffineTransform(translationX: -center.x, y: -center.y))
                .transformed(by: CGAffineTransform(rotationAngle: CGFloat(rotation.radians)))
        }

        let baseScale = max(target.width / rotated.extent.width, target.height / rotated.extent.height)
        let effectiveScale = baseScale * max(scale, allowsExposedEdges ? Self.minScale : 1)
        let scaled = rotated.transformed(by: CGAffineTransform(scaleX: effectiveScale, y: effectiveScale))

        let centeredX = (scaled.extent.width - target.width) / 2
        let centeredY = (scaled.extent.height - target.height) / 2
        // `offset` är en andel av målytan; CoreImages y-axel pekar uppåt,
        // SwiftUIs nedåt, därav minustecknet på Y.
        let panX = offset.width * target.width
        let panY = -offset.height * target.height

        let cropX: CGFloat
        let cropY: CGFloat
        if allowsExposedEdges {
            cropX = centeredX - panX
            cropY = centeredY - panY
        } else {
            let maxX = max(scaled.extent.width - target.width, 0)
            let maxY = max(scaled.extent.height - target.height, 0)
            cropX = min(max(centeredX - panX, 0), maxX)
            cropY = min(max(centeredY - panY, 0), maxY)
        }

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
