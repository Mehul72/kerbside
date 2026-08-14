import CoreGraphics
import Foundation

enum PanelColourSampler {
    static func hints(for regions: [CGRect], in image: CGImage) -> [PanelColourHint] {
        guard let bitmap = Bitmap(image: image, maximumDimension: 320) else {
            return Array(repeating: .none, count: regions.count)
        }
        return regions.map(bitmap.hint)
    }
}

private struct Bitmap {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init?(image: CGImage, maximumDimension: Int) {
        let scale = min(
            1,
            Double(maximumDimension) / Double(max(image.width, image.height))
        )
        let targetWidth = max(1, Int((Double(image.width) * scale).rounded()))
        let targetHeight = max(1, Int((Double(image.height) * scale).rounded()))

        let bytesPerRow = targetWidth * 4
        var storage = [UInt8](repeating: 0, count: bytesPerRow * targetHeight)
        let madeContext = storage.withUnsafeMutableBytes { buffer -> Bool in
            guard let baseAddress = buffer.baseAddress,
                  let context = CGContext(
                      data: baseAddress,
                      width: targetWidth,
                      height: targetHeight,
                      bitsPerComponent: 8,
                      bytesPerRow: bytesPerRow,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                          | CGBitmapInfo.byteOrder32Big.rawValue
                  )
            else { return false }

            // Keep row zero aligned with Vision's bottom-left coordinates.
            context.translateBy(x: 0, y: CGFloat(targetHeight))
            context.scaleBy(x: 1, y: -1)
            context.interpolationQuality = .medium
            context.draw(
                image,
                in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
            )
            return true
        }
        guard madeContext else { return nil }
        width = targetWidth
        height = targetHeight
        bytes = storage
    }

    func hint(in normalizedRegion: CGRect) -> PanelColourHint {
        let clipped = normalizedRegion.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !clipped.isNull, !clipped.isEmpty else { return .none }

        let minimumX = max(0, Int((clipped.minX * CGFloat(width)).rounded(.down)))
        let maximumX = min(width, Int((clipped.maxX * CGFloat(width)).rounded(.up)))
        let minimumY = max(0, Int((clipped.minY * CGFloat(height)).rounded(.down)))
        let maximumY = min(height, Int((clipped.maxY * CGFloat(height)).rounded(.up)))
        guard minimumX < maximumX, minimumY < maximumY else { return .none }

        let step = max(1, min(maximumX - minimumX, maximumY - minimumY) / 80)
        var red = 0
        var green = 0
        var samples = 0

        for y in stride(from: minimumY, to: maximumY, by: step) {
            for x in stride(from: minimumX, to: maximumX, by: step) {
                let offset = (y * width + x) * 4
                let r = Int(bytes[offset])
                let g = Int(bytes[offset + 1])
                let b = Int(bytes[offset + 2])
                if r > 80, r * 100 > g * 135, r * 100 > b * 120 { red += 1 }
                if g > 60, g * 100 > r * 115, g * 100 > b * 110 { green += 1 }
                samples += 1
            }
        }

        let threshold = max(3, samples / 400)
        let hasRed = red >= threshold
        let hasGreen = green >= threshold
        switch (hasRed, hasGreen) {
        case (true, true): return .mixed
        case (true, false): return .red
        case (false, true): return .green
        case (false, false): return .none
        }
    }
}
