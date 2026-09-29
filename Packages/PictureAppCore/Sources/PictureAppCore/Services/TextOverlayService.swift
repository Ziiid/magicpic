import CoreGraphics
import CoreText
import Foundation
import SwiftUI

/// Ritar en `TextOverlay` på en färdig bild (CoreText/CoreGraphics, så det
/// fungerar likadant på macOS och iOS). Måste ge SAMMA placering/storlek
/// som `TextOverlayLayer` visar i förhandsvisningen - teckenstorleken är
/// `overlay.size * bildbredd`, mittpunkten `overlay.offset` från bildens
/// mitt, och texten centreras på sin egen rad (bredd + (ascent-descent)/2).
public struct TextOverlayService {
    public init() {}

    /// Returnerar `image` oförändrad om texten är tom eller något går fel -
    /// en misslyckad textrendering ska aldrig stoppa själva exporten.
    public func apply(_ overlay: TextOverlay, to image: PlatformImage) -> PlatformImage {
        guard overlay.hasContent,
              let cgImage = image.cgImageRepresentation,
              let context = CGContext(
                  data: nil,
                  width: cgImage.width,
                  height: cgImage.height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return image }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let fontSize = overlay.size * width
        let font = CTFontCreateWithName(overlay.fontStyle.postScriptName as CFString, fontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): overlay.color.resolvedCGColor,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: overlay.text, attributes: attributes))

        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let textWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))

        // CoreGraphics y-axel pekar uppåt, SwiftUIs nedåt; rotation är
        // medsols i SwiftUI men moturs i CG - därav minustecknen.
        context.translateBy(x: width / 2 + overlay.offset.width * width, y: height / 2 - overlay.offset.height * height)
        context.rotate(by: -CGFloat(overlay.rotation.radians))

        if overlay.hasShadow {
            context.setShadow(
                offset: CGSize(width: 0, height: -fontSize * 0.06),
                blur: fontSize * 0.12,
                color: CGColor(gray: 0, alpha: 0.6)
            )
        }

        context.textPosition = CGPoint(x: -textWidth / 2, y: -(ascent - descent) / 2)
        CTLineDraw(line, context)

        guard let result = context.makeImage() else { return image }
        return PlatformImage(cgImageRepresentation: result)
    }
}
