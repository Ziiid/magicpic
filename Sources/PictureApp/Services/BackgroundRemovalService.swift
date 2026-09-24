import Vision
import AppKit
import CoreImage

/// Tar bort bakgrunden från en bild helt på enheten med Apples Vision-ramverk
/// (VNGenerateForegroundInstanceMaskRequest). Kräver ingen nätverksuppkoppling
/// eller extern tjänst och är i regel klart på under en sekund.
struct BackgroundRemovalService {
    struct RemovalError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    func removeBackground(from image: NSImage) throws -> NSImage {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw RemovalError(message: "Kunde inte läsa bilddata.")
        }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        guard let result = request.results?.first else {
            throw RemovalError(message: "Vision kunde inte analysera bilden.")
        }

        guard !result.allInstances.isEmpty else {
            throw RemovalError(message: "Hittade inget tydligt motiv att lyfta ur bakgrunden.")
        }

        let maskPixelBuffer = try result.generateScaledMaskForImage(
            forInstances: result.allInstances,
            from: handler
        )

        let ciImage = CIImage(cgImage: cgImage)
        let maskImage = CIImage(cvPixelBuffer: maskPixelBuffer)

        guard let filter = CIFilter(name: "CIBlendWithMask") else {
            throw RemovalError(message: "Kunde inte skapa bildfilter.")
        }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIImage(color: .clear).cropped(to: ciImage.extent), forKey: kCIInputBackgroundImageKey)
        filter.setValue(maskImage, forKey: kCIInputMaskImageKey)

        guard let outputCIImage = filter.outputImage else {
            throw RemovalError(message: "Kunde inte skapa den genomskinliga bilden.")
        }

        let context = CIContext()
        guard let outputCGImage = context.createCGImage(outputCIImage, from: ciImage.extent) else {
            throw RemovalError(message: "Kunde inte rendera resultatet.")
        }

        return NSImage(cgImage: outputCGImage, size: image.size)
    }
}
