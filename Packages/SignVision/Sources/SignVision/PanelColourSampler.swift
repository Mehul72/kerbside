import CoreGraphics
import Foundation

enum PanelColourSampler {
    struct Sample: Hashable, Sendable {
        var hint: PanelColourHint
        var evidence: PanelColourEvidence
    }

    static func samples(for regions: [CGRect], in image: CGImage) -> [Sample] {
        guard let bitmap = Bitmap(image: image, maximumDimension: 320) else {
            return Array(
                repeating: Sample(hint: .none, evidence: .none),
                count: regions.count
            )
        }
        return regions.map(bitmap.sample)
    }

    static func hints(for regions: [CGRect], in image: CGImage) -> [PanelColourHint] {
        samples(for: regions, in: image).map(\.hint)
    }
}

private struct Bitmap {
    private enum PixelColour: UInt8, Sendable {
        case none
        case red
        case green
    }

    private struct Component: Sendable {
        var colour: PixelColour
    }

    private struct PixelBounds {
        var minimumX: Int
        var maximumX: Int
        var minimumY: Int
        var maximumY: Int

        var width: Int { maximumX - minimumX }
        var height: Int { maximumY - minimumY }
        var sampleCount: Int { width * height }
    }

    private let width: Int
    private let height: Int
    private let colours: [PixelColour]
    private let componentLabels: [Int]
    private let components: [Component]

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

        var pixelColours = [PixelColour](repeating: .none, count: targetWidth * targetHeight)
        for index in pixelColours.indices {
            let offset = index * 4
            pixelColours[index] = Self.classify(
                red: Int(storage[offset]),
                green: Int(storage[offset + 1]),
                blue: Int(storage[offset + 2])
            )
        }
        let connected = Self.labelComponents(
            in: pixelColours,
            width: targetWidth,
            height: targetHeight
        )

        width = targetWidth
        height = targetHeight
        colours = pixelColours
        componentLabels = connected.labels
        components = connected.components
    }

    func sample(in normalizedRegion: CGRect) -> PanelColourSampler.Sample {
        guard let bounds = bounds(for: normalizedRegion) else {
            return PanelColourSampler.Sample(hint: .none, evidence: .none)
        }

        var red = 0
        var green = 0
        var componentCounts: [Int: Int] = [:]
        forEachPixel(in: bounds) { index in
            switch colours[index] {
            case .red: red += 1
            case .green: green += 1
            case .none: break
            }
            let componentID = componentLabels[index]
            if componentID >= 0 {
                componentCounts[componentID, default: 0] += 1
            }
        }

        let colourThreshold = max(4, (bounds.sampleCount + 99) / 100)
        let hasRed = red >= colourThreshold
        let hasGreen = green >= colourThreshold
        let hint: PanelColourHint = switch (hasRed, hasGreen) {
        case (true, true): .mixed
        case (true, false): .red
        case (false, true): .green
        case (false, false): .none
        }
        guard hint != .none,
              let dominant = dominantComponent(in: componentCounts, for: hint)
        else {
            return PanelColourSampler.Sample(hint: hint, evidence: .none)
        }

        let componentCount = componentCounts[dominant, default: 0]
        let chromaticCount = red + green
        let insideCoverage = ratio(componentCount, bounds.sampleCount)
        let componentShare = ratio(componentCount, chromaticCount)
        let band = max(1, min(bounds.width, bounds.height) / 12)
        let perimeterCoverage = minimumPerimeterCoverage(
            componentID: dominant,
            bounds: bounds,
            band: band
        )
        let outside = outsideCoverage(
            componentID: dominant,
            bounds: bounds,
            band: band
        )

        let coherentColour = componentShare >= 0.55
        let reachesEveryEdge = perimeterCoverage >= 0.025
        let enoughColour = insideCoverage >= 0.008
        let hasOutsideContext = outside.sampleCount > 0
        let separatedBoundary = outside.coverage <= max(0.01, perimeterCoverage * 0.2)
        let mixedIsDominant = hint != .mixed || componentShare >= 0.75
        let supportsStandalone = coherentColour
            && reachesEveryEdge
            && enoughColour
            && hasOutsideContext
            && separatedBoundary
            && mixedIsDominant
        let score: Float = supportsStandalone
            ? min(1, componentShare * 0.35 + perimeterCoverage + insideCoverage * 0.5)
            : 0

        return PanelColourSampler.Sample(
            hint: hint,
            evidence: PanelColourEvidence(
                insideCoverage: insideCoverage,
                outsideCoverage: outside.coverage,
                perimeterCoverage: perimeterCoverage,
                componentShare: componentShare,
                componentID: dominant,
                standaloneScore: score
            )
        )
    }

    private func dominantComponent(
        in counts: [Int: Int],
        for hint: PanelColourHint
    ) -> Int? {
        counts.keys
            .filter { componentID in
                switch hint {
                case .red: components[componentID].colour == .red
                case .green: components[componentID].colour == .green
                case .mixed: true
                case .none: false
                }
            }
            .sorted { lhs, rhs in
                let lhsCount = counts[lhs, default: 0]
                let rhsCount = counts[rhs, default: 0]
                if lhsCount != rhsCount { return lhsCount > rhsCount }
                return lhs < rhs
            }
            .first
    }

    private func minimumPerimeterCoverage(
        componentID: Int,
        bounds: PixelBounds,
        band: Int
    ) -> Float {
        let edges = [
            PixelBounds(
                minimumX: bounds.minimumX,
                maximumX: bounds.maximumX,
                minimumY: bounds.minimumY,
                maximumY: min(bounds.maximumY, bounds.minimumY + band)
            ),
            PixelBounds(
                minimumX: bounds.minimumX,
                maximumX: bounds.maximumX,
                minimumY: max(bounds.minimumY, bounds.maximumY - band),
                maximumY: bounds.maximumY
            ),
            PixelBounds(
                minimumX: bounds.minimumX,
                maximumX: min(bounds.maximumX, bounds.minimumX + band),
                minimumY: bounds.minimumY,
                maximumY: bounds.maximumY
            ),
            PixelBounds(
                minimumX: max(bounds.minimumX, bounds.maximumX - band),
                maximumX: bounds.maximumX,
                minimumY: bounds.minimumY,
                maximumY: bounds.maximumY
            ),
        ]

        return edges.map { edge in
            var matches = 0
            forEachPixel(in: edge) { index in
                if componentLabels[index] == componentID { matches += 1 }
            }
            return ratio(matches, edge.sampleCount)
        }.min() ?? 0
    }

    private func outsideCoverage(
        componentID: Int,
        bounds: PixelBounds,
        band: Int
    ) -> (coverage: Float, sampleCount: Int) {
        let expanded = PixelBounds(
            minimumX: max(0, bounds.minimumX - band),
            maximumX: min(width, bounds.maximumX + band),
            minimumY: max(0, bounds.minimumY - band),
            maximumY: min(height, bounds.maximumY + band)
        )
        var matches = 0
        var samples = 0
        for y in expanded.minimumY..<expanded.maximumY {
            for x in expanded.minimumX..<expanded.maximumX {
                guard x < bounds.minimumX || x >= bounds.maximumX
                    || y < bounds.minimumY || y >= bounds.maximumY
                else { continue }
                let index = y * width + x
                if componentLabels[index] == componentID { matches += 1 }
                samples += 1
            }
        }
        return (ratio(matches, samples), samples)
    }

    private func bounds(for normalizedRegion: CGRect) -> PixelBounds? {
        let clipped = normalizedRegion.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !clipped.isNull, !clipped.isEmpty else { return nil }

        let result = PixelBounds(
            minimumX: max(0, Int((clipped.minX * CGFloat(width)).rounded(.down))),
            maximumX: min(width, Int((clipped.maxX * CGFloat(width)).rounded(.up))),
            minimumY: max(0, Int((clipped.minY * CGFloat(height)).rounded(.down))),
            maximumY: min(height, Int((clipped.maxY * CGFloat(height)).rounded(.up)))
        )
        return result.sampleCount > 0 ? result : nil
    }

    private func forEachPixel(in bounds: PixelBounds, _ body: (Int) -> Void) {
        for y in bounds.minimumY..<bounds.maximumY {
            for x in bounds.minimumX..<bounds.maximumX {
                body(y * width + x)
            }
        }
    }

    private func ratio(_ numerator: Int, _ denominator: Int) -> Float {
        guard denominator > 0 else { return 0 }
        return Float(numerator) / Float(denominator)
    }

    private static func labelComponents(
        in colours: [PixelColour],
        width: Int,
        height: Int
    ) -> (labels: [Int], components: [Component]) {
        var labels = [Int](repeating: -1, count: colours.count)
        var components: [Component] = []

        for start in colours.indices where colours[start] != .none && labels[start] == -1 {
            let componentID = components.count
            let colour = colours[start]
            var stack = [start]
            labels[start] = componentID

            while let index = stack.popLast() {
                let x = index % width
                let y = index / width
                for offsetY in -1...1 {
                    for offsetX in -1...1 where offsetX != 0 || offsetY != 0 {
                        let neighbourX = x + offsetX
                        let neighbourY = y + offsetY
                        guard neighbourX >= 0, neighbourX < width,
                              neighbourY >= 0, neighbourY < height
                        else { continue }
                        let neighbour = neighbourY * width + neighbourX
                        guard labels[neighbour] == -1, colours[neighbour] == colour else {
                            continue
                        }
                        labels[neighbour] = componentID
                        stack.append(neighbour)
                    }
                }
            }

            components.append(Component(colour: colour))
        }
        return (labels, components)
    }

    /// Hue-like dominance rejects brown branches while retaining shaded sign
    /// paint; boundary and component evidence handle natural green foliage.
    private static func classify(red r: Int, green g: Int, blue b: Int) -> PixelColour {
        let maximum = max(r, g, b)
        let minimum = min(r, g, b)
        let chroma = maximum - minimum

        if r == maximum,
           r >= 75,
           chroma >= 25,
           r - g >= 20,
           r - b >= 20,
           abs(g - b) * 100 <= chroma * 45 {
            return .red
        }

        if g == maximum,
           g >= 65,
           chroma >= 25,
           g - r >= 18,
           g - b >= 15 {
            return .green
        }

        return .none
    }
}
