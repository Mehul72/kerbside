import CoreGraphics
import CoreImage
import Foundation
import ImageIO

enum ImagePreprocessor {
    /// Applies capture orientation and limits the longest edge before Vision
    /// work. Camera photos are far larger than parking-sign OCR needs.
    static func prepare(
        _ image: CGImage,
        orientation: CGImagePropertyOrientation,
        maximumDimension: CGFloat = 2_048
    ) -> CGImage? {
        var input = CIImage(cgImage: image).oriented(orientation)
        let extent = input.extent.integral
        guard extent.width > 0, extent.height > 0 else { return nil }

        input = input.transformed(
            by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY)
        )
        let longestEdge = max(extent.width, extent.height)
        let scale = min(1, maximumDimension / longestEdge)
        if scale < 1 {
            input = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }

        let outputExtent = CGRect(
            origin: .zero,
            size: CGSize(width: extent.width * scale, height: extent.height * scale)
        ).integral
        let context = CIContext(options: [.cacheIntermediates: false])
        return context.createCGImage(input, from: outputExtent)
    }
}
