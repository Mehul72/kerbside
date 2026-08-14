import CoreGraphics
import Foundation

/// Finds graphical arrows after text has already been grouped into panels.
///
/// Arrow evidence never participates in segmentation. A detection is attached
/// only when one trusted physical face owns it; every ambiguous case is left
/// unspecified.
enum PanelArrowDetector {
    static func annotate(_ blocks: [PanelBlock], in image: CGImage) -> [PanelBlock] {
        guard let raster = ArrowRaster(image: image, maximumDimension: 768) else {
            return blocks
        }

        let trustedIndices = blocks.indices.filter { index in
            guard let region = blocks[index].sourceRegion else { return false }
            guard region.colourEvidence.supportsStandalonePanel else { return false }
            return region.colourHint == .red || region.colourHint == .green
        }
        guard !trustedIndices.isEmpty else { return blocks }

        let textBoxes = blocks.flatMap { block in
            block.lines.compactMap { line in
                line.text.contains(where: { $0.isLetter || $0.isNumber })
                    ? line.boundingBox
                    : nil
            }
        }
        let observations = trustedIndices.flatMap { index in
            guard let region = blocks[index].sourceRegion else {
                return [ArrowObservation]()
            }
            return raster.observations(
                in: region.boundingBox,
                panelColour: region.colourHint,
                excluding: textBoxes
            )
        }
        let arrows = deduplicate(observations)

        var evidence: [Int: [ArrowObservation]] = [:]
        for arrow in arrows {
            let owners = trustedIndices.filter { index in
                guard let region = blocks[index].sourceRegion else { return false }
                return containment(of: arrow.boundingBox, in: region.boundingBox) >= 0.9
            }
            guard owners.count == 1, let owner = owners.first else { continue }
            evidence[owner, default: []].append(arrow)
        }

        var annotated = blocks
        for (index, observations) in evidence {
            let unique = Set(observations.map(\.direction))
            guard unique.count == 1 else { continue }
            annotated[index].visualDirection = unique.first

            let keptLines = annotated[index].lines.filter { line in
                guard isShaftOnly(line.text) else { return true }
                return !observations.contains { observation in
                    containment(of: line.boundingBox, in: observation.boundingBox) >= 0.5
                }
            }
            if !keptLines.isEmpty,
               keptLines.count != annotated[index].lines.count {
                annotated[index].parserTextOverride = keptLines
                    .map(\.text)
                    .joined(separator: "\n")
            }
        }
        return annotated
    }

    private static func deduplicate(
        _ observations: [ArrowObservation]
    ) -> [ArrowObservation] {
        let ordered = observations.sorted(by: observationComesFirst)
        var clusters: [[ArrowObservation]] = []

        for observation in ordered {
            let matching = clusters.indices.filter { clusterIndex in
                clusters[clusterIndex].contains { member in
                    stronglyOverlaps(observation.boundingBox, member.boundingBox)
                }
            }
            if matching.isEmpty {
                clusters.append([observation])
            } else if matching.count == 1, let index = matching.first {
                clusters[index].append(observation)
            }
        }

        return clusters.compactMap { cluster in
            guard Set(cluster.map(\.direction)).count == 1 else { return nil }
            return cluster.sorted(by: observationComesFirst).first
        }
    }

    private static func observationComesFirst(
        _ lhs: ArrowObservation,
        _ rhs: ArrowObservation
    ) -> Bool {
        if lhs.confidence != rhs.confidence { return lhs.confidence > rhs.confidence }
        if lhs.boundingBox.maxY != rhs.boundingBox.maxY {
            return lhs.boundingBox.maxY > rhs.boundingBox.maxY
        }
        if lhs.boundingBox.minX != rhs.boundingBox.minX {
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }
        return lhs.direction.rawValue < rhs.direction.rawValue
    }

    private static func containment(of inner: CGRect, in outer: CGRect) -> CGFloat {
        let intersection = inner.intersection(outer)
        guard !intersection.isNull, !intersection.isEmpty else { return 0 }
        let innerArea = inner.width * inner.height
        guard innerArea > 0 else { return 0 }
        return intersection.width * intersection.height / innerArea
    }

    private static func isShaftOnly(_ text: String) -> Bool {
        let characters = text.filter { !$0.isWhitespace }
        guard !characters.isEmpty, characters.count <= 4 else { return false }
        return characters.allSatisfy { "-–—−_=".contains($0) }
    }

    private static func stronglyOverlaps(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull, !intersection.isEmpty else { return false }
        let intersectionArea = intersection.width * intersection.height
        let smallerArea = min(lhs.width * lhs.height, rhs.width * rhs.height)
        guard smallerArea > 0 else { return false }
        return intersectionArea / smallerArea >= 0.8
    }
}

private struct ArrowObservation: Hashable, Sendable {
    var direction: VisualDirection
    var confidence: Float
    var boundingBox: CGRect
}

private struct ArrowRaster {
    private enum Polarity: CaseIterable {
        case light
        case ink
    }

    private struct Pixel {
        var red: Int
        var green: Int
        var blue: Int

        var maximum: Int { max(red, green, blue) }
        var minimum: Int { min(red, green, blue) }
        var chroma: Int { maximum - minimum }
        var luminance: Int { (red * 54 + green * 183 + blue * 19) / 256 }

        var isLightNeutral: Bool {
            luminance >= 150 && chroma <= 70
        }

        var isInk: Bool {
            luminance <= 130 || chroma >= 50
        }

        var isRed: Bool {
            red == maximum
                && red >= 75
                && chroma >= 25
                && red - green >= 20
                && red - blue >= 20
                && abs(green - blue) * 100 <= chroma * 45
        }

        var isGreen: Bool {
            green == maximum
                && green >= 65
                && chroma >= 25
                && green - red >= 18
                && green - blue >= 15
        }
    }

    private struct Bounds {
        var minimumX: Int
        var maximumX: Int
        var minimumY: Int
        var maximumY: Int

        var width: Int { maximumX - minimumX }
        var height: Int { maximumY - minimumY }
        var area: Int { width * height }

        func contains(x: Int, y: Int) -> Bool {
            x >= minimumX && x < maximumX && y >= minimumY && y < maximumY
        }
    }

    private struct Component {
        var pixels: [Int]
        var bounds: Bounds
    }

    private struct ShapeScore {
        var direction: VisualDirection
        var score: Float
    }

    private let width: Int
    private let height: Int
    private let pixels: [Pixel]

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
        pixels = stride(from: 0, to: storage.count, by: 4).map { offset in
            Pixel(
                red: Int(storage[offset]),
                green: Int(storage[offset + 1]),
                blue: Int(storage[offset + 2])
            )
        }
    }

    func observations(
        in normalizedPanel: CGRect,
        panelColour: PanelColourHint,
        excluding normalizedTextBoxes: [CGRect]
    ) -> [ArrowObservation] {
        guard let panel = bounds(for: normalizedPanel) else { return [] }
        let inset = max(2, min(panel.width, panel.height) * 6 / 100)
        let interior = Bounds(
            minimumX: panel.minimumX + inset,
            maximumX: panel.maximumX - inset,
            minimumY: panel.minimumY + inset,
            maximumY: panel.maximumY - inset
        )
        guard interior.width >= 32, interior.height >= 32 else { return [] }

        let excluded = normalizedTextBoxes.compactMap { box -> Bounds? in
            let expanded = box.insetBy(
                dx: -max(box.width * 0.08, normalizedPanel.width * 0.015),
                dy: -max(box.height * 0.35, normalizedPanel.height * 0.008)
            )
            guard expanded.intersects(normalizedPanel) else { return nil }
            return bounds(for: expanded)
        }

        return Polarity.allCases.flatMap { polarity in
            components(
                in: interior,
                polarity: polarity,
                excluding: excluded
            ).compactMap { component in
                observation(
                    for: component,
                    in: interior,
                    polarity: polarity,
                    panelColour: panelColour,
                    excluding: excluded
                )
            }
        }
    }

    private func components(
        in interior: Bounds,
        polarity: Polarity,
        excluding excluded: [Bounds]
    ) -> [Component] {
        let localWidth = interior.width
        let localHeight = interior.height
        var mask = [UInt8](repeating: 0, count: interior.area)

        for localY in 0..<localHeight {
            let y = interior.minimumY + localY
            for localX in 0..<localWidth {
                let x = interior.minimumX + localX
                guard !excluded.contains(where: { $0.contains(x: x, y: y) }) else {
                    continue
                }
                let pixel = pixels[y * width + x]
                let foreground = switch polarity {
                case .light: pixel.isLightNeutral
                case .ink: pixel.isInk
                }
                if foreground { mask[localY * localWidth + localX] = 1 }
            }
        }

        var visited = [UInt8](repeating: 0, count: mask.count)
        var result: [Component] = []
        for start in mask.indices where mask[start] == 1 && visited[start] == 0 {
            var stack = [start]
            var members: [Int] = []
            var minimumX = start % localWidth
            var maximumX = minimumX
            var minimumY = start / localWidth
            var maximumY = minimumY
            visited[start] = 1

            while let index = stack.popLast() {
                members.append(index)
                let x = index % localWidth
                let y = index / localWidth
                minimumX = min(minimumX, x)
                maximumX = max(maximumX, x)
                minimumY = min(minimumY, y)
                maximumY = max(maximumY, y)

                for offsetY in -1...1 {
                    for offsetX in -1...1 where offsetX != 0 || offsetY != 0 {
                        let neighbourX = x + offsetX
                        let neighbourY = y + offsetY
                        guard neighbourX >= 0, neighbourX < localWidth,
                              neighbourY >= 0, neighbourY < localHeight
                        else { continue }
                        let neighbour = neighbourY * localWidth + neighbourX
                        guard mask[neighbour] == 1, visited[neighbour] == 0 else {
                            continue
                        }
                        visited[neighbour] = 1
                        stack.append(neighbour)
                    }
                }
            }

            result.append(
                Component(
                    pixels: members,
                    bounds: Bounds(
                        minimumX: minimumX,
                        maximumX: maximumX + 1,
                        minimumY: minimumY,
                        maximumY: maximumY + 1
                    )
                )
            )
        }
        return result
    }

    private func observation(
        for component: Component,
        in interior: Bounds,
        polarity: Polarity,
        panelColour: PanelColourHint,
        excluding excluded: [Bounds]
    ) -> ArrowObservation? {
        let box = component.bounds
        let widthRatio = Float(box.width) / Float(interior.width)
        let heightRatio = Float(box.height) / Float(interior.height)
        let aspectRatio = Float(box.width) / Float(max(1, box.height))
        let fill = Float(component.pixels.count) / Float(max(1, box.area))
        let minimumPixels = max(12, interior.area / 2_000)
        let clearance = max(1, min(interior.width, interior.height) / 100)

        guard box.minimumX >= clearance,
              box.minimumY >= clearance,
              box.maximumX <= interior.width - clearance,
              box.maximumY <= interior.height - clearance,
              component.pixels.count >= minimumPixels,
              (0.16...0.86).contains(widthRatio),
              (0.035...0.30).contains(heightRatio),
              (1.7...9).contains(aspectRatio),
              (0.10...0.78).contains(fill)
        else { return nil }

        let globalBounds = Bounds(
            minimumX: interior.minimumX + box.minimumX,
            maximumX: interior.minimumX + box.maximumX,
            minimumY: interior.minimumY + box.minimumY,
            maximumY: interior.minimumY + box.maximumY
        )
        let support = surroundSupport(
            around: globalBounds,
            inside: interior,
            polarity: polarity,
            panelColour: panelColour,
            excluding: excluded
        )
        guard support >= 0.45 else { return nil }

        let mask = normalizedMask(
            for: component,
            localWidth: interior.width,
            gridWidth: 48,
            gridHeight: 24
        )
        guard let shape = classify(mask: mask, width: 48, height: 24) else {
            return nil
        }

        return ArrowObservation(
            direction: shape.direction,
            confidence: shape.score,
            boundingBox: CGRect(
                x: CGFloat(globalBounds.minimumX) / CGFloat(width),
                y: CGFloat(globalBounds.minimumY) / CGFloat(height),
                width: CGFloat(globalBounds.width) / CGFloat(width),
                height: CGFloat(globalBounds.height) / CGFloat(height)
            )
        )
    }

    private func normalizedMask(
        for component: Component,
        localWidth: Int,
        gridWidth: Int,
        gridHeight: Int
    ) -> [Bool] {
        var result = [Bool](repeating: false, count: gridWidth * gridHeight)
        for index in component.pixels {
            let x = index % localWidth - component.bounds.minimumX
            let y = index / localWidth - component.bounds.minimumY
            let gridX = min(gridWidth - 1, x * gridWidth / max(1, component.bounds.width))
            let gridY = min(gridHeight - 1, y * gridHeight / max(1, component.bounds.height))
            result[gridY * gridWidth + gridX] = true
        }
        return result
    }

    private func classify(mask: [Bool], width: Int, height: Int) -> ShapeScore? {
        let symmetry = verticalSymmetry(of: mask, width: width, height: height)
        guard symmetry >= 0.55 else { return nil }

        let left = bestTemplateScore(
            mask: mask,
            direction: .left,
            width: width,
            height: height
        )
        let right = bestTemplateScore(
            mask: mask,
            direction: .right,
            width: width,
            height: height
        )
        let bidirectional = bestTemplateScore(
            mask: mask,
            direction: .bidirectional,
            width: width,
            height: height
        )
        let ranked = [
            ShapeScore(direction: .left, score: left),
            ShapeScore(direction: .right, score: right),
            ShapeScore(direction: .bidirectional, score: bidirectional),
        ].sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.direction.rawValue < rhs.direction.rawValue
        }
        guard let best = ranked.first, ranked.count > 1 else { return nil }
        let minimumMargin: Float = best.direction == .bidirectional ? 0.04 : 0.06
        guard
              best.score >= 0.42,
              best.score - ranked[1].score >= minimumMargin,
              geometrySupports(
                  best.direction,
                  mask: mask,
                  width: width,
                  height: height
              )
        else { return nil }

        return ShapeScore(
            direction: best.direction,
            score: best.score * 0.75 + symmetry * 0.25
        )
    }

    private func bestTemplateScore(
        mask: [Bool],
        direction: VisualDirection,
        width: Int,
        height: Int
    ) -> Float {
        let headFractions: [Float] = direction == .bidirectional
            ? [0.22, 0.28, 0.34]
            : [0.25, 0.32, 0.40]
        let shaftFractions: [Float] = [0.10, 0.16, 0.22]
        return headFractions.flatMap { head in
            shaftFractions.map { shaft in
                intersectionOverUnion(
                    mask,
                    template(
                        direction: direction,
                        headFraction: head,
                        shaftFraction: shaft,
                        width: width,
                        height: height
                    )
                )
            }
        }.max() ?? 0
    }

    private func template(
        direction: VisualDirection,
        headFraction: Float,
        shaftFraction: Float,
        width: Int,
        height: Int
    ) -> [Bool] {
        var result = [Bool](repeating: false, count: width * height)
        let center = Float(height - 1) / 2
        let headWidth = max(2, Int(Float(width) * headFraction))
        let shaftHalfHeight = max(1, Int(Float(height) * shaftFraction))

        for y in 0..<height {
            for x in 0..<width {
                let distance = abs(Float(y) - center)
                let inShaft = distance <= Float(shaftHalfHeight)
                let leftHalfHeight = Float(x) / Float(max(1, headWidth - 1)) * center
                let rightX = width - 1 - x
                let rightHalfHeight = Float(rightX) / Float(max(1, headWidth - 1)) * center

                let filled = switch direction {
                case .left:
                    x < headWidth ? distance <= leftHalfHeight : inShaft
                case .right:
                    rightX < headWidth ? distance <= rightHalfHeight : inShaft
                case .bidirectional:
                    if x < headWidth {
                        distance <= leftHalfHeight
                    } else if rightX < headWidth {
                        distance <= rightHalfHeight
                    } else {
                        inShaft
                    }
                }
                result[y * width + x] = filled
            }
        }
        return result
    }

    private func geometrySupports(
        _ direction: VisualDirection,
        mask: [Bool],
        width: Int,
        height: Int
    ) -> Bool {
        let band = max(2, width * 30 / 100)
        let middleStart = width * 38 / 100
        let middleEnd = width * 62 / 100
        let leftSpan = verticalSpan(mask, xRange: 0..<band, width: width, height: height)
        let rightSpan = verticalSpan(
            mask,
            xRange: (width - band)..<width,
            width: width,
            height: height
        )
        let middleSpan = verticalSpan(
            mask,
            xRange: middleStart..<middleEnd,
            width: width,
            height: height
        )
        let tipBand = max(2, width * 8 / 100)
        let shoulderStart = width * 16 / 100
        let shoulderEnd = width * 42 / 100
        let leftTapers = headTapers(
            tipSpan: verticalSpan(
                mask,
                xRange: 0..<tipBand,
                width: width,
                height: height
            ),
            shoulderSpan: verticalSpan(
                mask,
                xRange: shoulderStart..<shoulderEnd,
                width: width,
                height: height
            )
        )
        let rightTapers = headTapers(
            tipSpan: verticalSpan(
                mask,
                xRange: (width - tipBand)..<width,
                width: width,
                height: height
            ),
            shoulderSpan: verticalSpan(
                mask,
                xRange: (width - shoulderEnd)..<(width - shoulderStart),
                width: width,
                height: height
            )
        )

        switch direction {
        case .left:
            return leftTapers
                && leftSpan >= 0.65
                && rightSpan <= 0.55
                && leftSpan - rightSpan >= 0.22
                && middleSpan <= 0.58
        case .right:
            return rightTapers
                && rightSpan >= 0.65
                && leftSpan <= 0.55
                && rightSpan - leftSpan >= 0.22
                && middleSpan <= 0.58
        case .bidirectional:
            return leftTapers
                && rightTapers
                && leftSpan >= 0.62
                && rightSpan >= 0.62
                && middleSpan <= 0.55
        }
    }

    private func headTapers(tipSpan: Float, shoulderSpan: Float) -> Bool {
        tipSpan <= 0.38
            && shoulderSpan >= 0.70
            && shoulderSpan - tipSpan >= 0.35
    }

    private func verticalSpan(
        _ mask: [Bool],
        xRange: Range<Int>,
        width: Int,
        height: Int
    ) -> Float {
        var minimumY = height
        var maximumY = -1
        for y in 0..<height {
            for x in xRange where mask[y * width + x] {
                minimumY = min(minimumY, y)
                maximumY = max(maximumY, y)
            }
        }
        guard maximumY >= minimumY else { return 0 }
        return Float(maximumY - minimumY + 1) / Float(height)
    }

    private func verticalSymmetry(of mask: [Bool], width: Int, height: Int) -> Float {
        var intersection = 0
        var union = 0
        for y in 0..<height {
            let mirroredY = height - 1 - y
            for x in 0..<width {
                let value = mask[y * width + x]
                let mirrored = mask[mirroredY * width + x]
                if value && mirrored { intersection += 1 }
                if value || mirrored { union += 1 }
            }
        }
        return ratio(intersection, union)
    }

    private func intersectionOverUnion(_ lhs: [Bool], _ rhs: [Bool]) -> Float {
        var intersection = 0
        var union = 0
        for index in lhs.indices {
            if lhs[index] && rhs[index] { intersection += 1 }
            if lhs[index] || rhs[index] { union += 1 }
        }
        return ratio(intersection, union)
    }

    private func surroundSupport(
        around component: Bounds,
        inside interior: Bounds,
        polarity: Polarity,
        panelColour: PanelColourHint,
        excluding excluded: [Bounds]
    ) -> Float {
        let ring = max(2, min(component.width, component.height) / 6)
        let expanded = Bounds(
            minimumX: max(interior.minimumX, component.minimumX - ring),
            maximumX: min(interior.maximumX, component.maximumX + ring),
            minimumY: max(interior.minimumY, component.minimumY - ring),
            maximumY: min(interior.maximumY, component.maximumY + ring)
        )
        var supported = 0
        var sampled = 0

        for y in expanded.minimumY..<expanded.maximumY {
            for x in expanded.minimumX..<expanded.maximumX {
                guard !component.contains(x: x, y: y),
                      !excluded.contains(where: { $0.contains(x: x, y: y) })
                else { continue }
                let pixel = pixels[y * width + x]
                let matches = switch polarity {
                case .light:
                    panelColour == .red ? pixel.isRed : pixel.isGreen
                case .ink:
                    pixel.isLightNeutral
                }
                if matches { supported += 1 }
                sampled += 1
            }
        }
        guard sampled >= 12 else { return 0 }
        return ratio(supported, sampled)
    }

    private func bounds(for normalized: CGRect) -> Bounds? {
        let clipped = normalized.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !clipped.isNull, !clipped.isEmpty else { return nil }
        let result = Bounds(
            minimumX: max(0, Int((clipped.minX * CGFloat(width)).rounded(.down))),
            maximumX: min(width, Int((clipped.maxX * CGFloat(width)).rounded(.up))),
            minimumY: max(0, Int((clipped.minY * CGFloat(height)).rounded(.down))),
            maximumY: min(height, Int((clipped.maxY * CGFloat(height)).rounded(.up)))
        )
        return result.area > 0 ? result : nil
    }

    private func ratio(_ numerator: Int, _ denominator: Int) -> Float {
        guard denominator > 0 else { return 0 }
        return Float(numerator) / Float(denominator)
    }
}
