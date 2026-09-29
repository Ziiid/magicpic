import CoreGraphics
import Foundation
import SwiftUI

/// Ritar en `LogoOverlay` på en färdig bild (CoreGraphics - samma på macOS och
/// iOS). Måste ge SAMMA placering/storlek som `LogoOverlayLayer` visar i
/// förhandsvisningen: bredd = `logo.size * bildbredd`, höjd efter logotypens
/// eget bildförhållande, mittpunkt = bildens mitt + `logo.offset`.
public struct LogoOverlayService {
    public init() {}

    /// Returnerar `image` oförändrad om något går fel - en misslyckad
    /// logotyprendering ska aldrig stoppa själva exporten.
    public func apply(_ logo: LogoOverlay, to image: PlatformImage) -> PlatformImage {
        guard let cgImage = image.cgImageRepresentation,
              let logoCG = logo.image.cgImageRepresentation,
              logoCG.width > 0, logoCG.height > 0,
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

        let logoWidth = logo.size * width
        let logoHeight = logoWidth * CGFloat(logoCG.height) / CGFloat(logoCG.width)

        // CoreGraphics y-axel pekar uppåt, SwiftUIs nedåt; rotation är
        // medsols i SwiftUI men moturs i CG - därav minustecknen.
        context.translateBy(x: width / 2 + logo.offset.width * width, y: height / 2 - logo.offset.height * height)
        context.rotate(by: -CGFloat(logo.rotation.radians))
        if logo.isFlipped {
            context.scaleBy(x: -1, y: 1)
        }
        context.interpolationQuality = .high
        context.draw(logoCG, in: CGRect(x: -logoWidth / 2, y: -logoHeight / 2, width: logoWidth, height: logoHeight))

        guard let result = context.makeImage() else { return image }
        return PlatformImage(cgImageRepresentation: result)
    }
}
