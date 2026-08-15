import CoreGraphics
import Foundation

/// Finds graphical arrows after text has already been grouped into panels.
///
/// Arrow evidence never participates in segmentation. A detection is attached
/// only when one trusted physical face owns it; every ambiguous case is left
/// unspecified.
enum ArrowTrace {
    /// Diagnostics only. Set KERBSIDE_ARROW_TRACE=1 to see why a candidate
    /// shape was or was not taken for an arrow.
    static let isOn = ProcessInfo.processInfo.environment["KERBSIDE_ARROW_TRACE"] == "1"
}

enum PanelArrowDetector {
    /// Where a block's arrow may be looked for, and what colour surrounds it.
    struct SearchFace {
        var boundingBox: CGRect
        var colour: PanelColourHint
    }

    static func annotate(
        _ blocks: [PanelBlock],
        regions: [PanelRegion] = [],
        in image: CGImage
    ) -> [PanelBlock] {
        guard let raster = ArrowRaster(image: image, maximumDimension: 768) else {
            return blocks
        }

        let faces = searchFaces(for: blocks, among: regions)
        guard !faces.isEmpty else { return blocks }

        let textBoxes = blocks.flatMap { block in
            block.lines.compactMap { line in
                line.text.contains(where: { $0.isLetter || $0.isNumber })
                    ? line.boundingBox
                    : nil
            }
        }
        let observations = faces.keys.sorted().flatMap { index -> [ArrowObservation] in
            guard let face = faces[index] else { return [] }
            return raster.observations(
                in: face.boundingBox,
                panelColour: face.colour,
                excluding: textBoxes
            )
        }
        let arrows = deduplicate(observations)

        var evidence: [Int: [ArrowObservation]] = [:]
        for arrow in arrows {
            let owners = faces.keys.filter { index in
                guard let face = faces[index] else { return false }
                return containment(of: arrow.boundingBox, in: face.boundingBox) >= 0.9
            }
            // Still exactly one owner or nothing. An arrow that several faces
            // could claim says nothing about which kerb it scopes.
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

    /// Chooses the area to search for each block's arrow.
    ///
    /// The face is the *largest* candidate rectangle around the block's text,
    /// not the tightest and not necessarily a trusted coloured one. Largest,
    /// because an arrow sits below the words in the blank half of the plate,
    /// and the tightest rectangle is usually the coloured band around the text
    /// itself, which excludes exactly the area the arrow is in.
    ///
    /// On a pole of several signs the largest enclosing rectangle tends to be
    /// shared, so every block claims the same arrow and ownership refuses it.
    /// That is the intended outcome: no direction beats a guessed one.
    static func searchFaces(
        for blocks: [PanelBlock],
        among regions: [PanelRegion]
    ) -> [Int: SearchFace] {
        var faces: [Int: SearchFace] = [:]

        func area(_ rect: CGRect) -> CGFloat { rect.width * rect.height }

        for index in blocks.indices {
            var best: SearchFace?

            // A detector-backed colourless child (for example an information
            // sticker inside a parking plate) is a real separate result, but
            // it must not claim the parent plate's arrow.
            if let source = blocks[index].sourceRegion,
               source.colourHint != .red,
               source.colourHint != .green {
                continue
            }

            // A trusted coloured rectangle is good evidence of a real face, but
            // on a sign whose top half is a coloured banner it describes only
            // that banner. It is a candidate, not the answer.
            if let region = blocks[index].sourceRegion,
               region.colourEvidence.supportsStandalonePanel,
               region.colourHint == .red || region.colourHint == .green {
                best = SearchFace(
                    boundingBox: region.boundingBox,
                    colour: region.colourHint
                )
            }

            let text = blocks[index].boundingBox
            if text.width > 0, text.height > 0 {
                // The text centre, not the whole text box. Vision pads its
                // text rectangles, so on a sign photographed small the words
                // overshoot the plate edges and no rectangle fully contains
                // them. Requiring full containment threw away the actual
                // plate, which is the one face worth searching.
                let centre = CGPoint(x: text.midX, y: text.midY)
                let enclosing = regions.filter { region in
                    region.boundingBox.contains(centre)
                        && area(region.boundingBox) > area(text) * 1.2
                }
                if let plate = enclosing.max(by: { area($0.boundingBox) < area($1.boundingBox) }),
                   best.map({ area(plate.boundingBox) > area($0.boundingBox) }) ?? true {
                    best = SearchFace(
                        boundingBox: plate.boundingBox,
                        colour: plate.colourHint
                    )
                }

                // Last resort, the block's own extent. On a tilted sign Vision
                // returns the arrow as a stray character, which swells the
                // block to the size of the plate and leaves no rectangle
                // bigger than it. That block box is the plate, so search it
                // rather than giving up on the sign entirely.
                //
                // Only when the photograph holds a single block. On a pole this
                // would hand overlapping faces to several blocks, and an arrow
                // that two faces can claim gets refused rather than assigned.
                if blocks.count == 1,
                   best.map({ area(text) > area($0.boundingBox) }) ?? true {
                    best = SearchFace(
                        boundingBox: text,
                        colour: blocks[index].colourHint
                    )
                }
            }

            // The widest enclosing face wins. An arrow lives in the blank half
            // of the plate, below the words, so searching anything smaller than
            // the whole face looks everywhere except where the arrow is.
            if ArrowTrace.isOn {
                let text = blocks[index].boundingBox
                let chosen = best.map { "\($0.boundingBox)" } ?? "NO FACE FOUND"
                let line = "face for block \(index): \(chosen)  text \(text)  "
                    + "candidates \(regions.count)\n"
                FileHandle.standardError.write(Data(line.utf8))
            }
            if let best { faces[index] = best }
        }
        return faces
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

        return Polarity.allCases.flatMap { polarity -> [ArrowObservation] in
            let found = components(
                in: interior,
                polarity: polarity,
                excluding: excluded
            )
            return found.compactMap { component in
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

        func trace(_ verdict: String) {
            guard ArrowTrace.isOn else { return }
            FileHandle.standardError.write(Data("""
                arrow candidate \(polarity) \
                px=\(component.pixels.count)/\(minimumPixels) \
                w=\(String(format: "%.3f", widthRatio)) \
                h=\(String(format: "%.3f", heightRatio)) \
                aspect=\(String(format: "%.2f", aspectRatio)) \
                fill=\(String(format: "%.2f", fill)) \
                -> \(verdict)\n
                """.utf8))
        }

        let touchesLeft = box.minimumX < clearance
        let touchesRight = box.maximumX > interior.width - clearance
        guard box.minimumY >= clearance,
              box.maximumY <= interior.height - clearance,
              !(touchesLeft && touchesRight),
              (!(touchesLeft || touchesRight) || widthRatio <= 0.95)
        else {
            trace("rejected: touches the panel edge")
            return nil
        }
        guard component.pixels.count >= minimumPixels else {
            trace("rejected: too few pixels")
            return nil
        }
        // NSW arrows are drawn nearly edge to edge inside the plate. The old
        // ceiling of 0.86 excluded the standard artwork, where the arrow spans
        // 97% of the face. A full width bar is still rejected, by the taper
        // test rather than by its size.
        guard (0.16...0.98).contains(widthRatio) else {
            trace("rejected: width ratio")
            return nil
        }
        guard (0.035...0.30).contains(heightRatio) else {
            trace("rejected: height ratio")
            return nil
        }
        guard (1.7...9).contains(aspectRatio) else {
            trace("rejected: aspect ratio")
            return nil
        }
        guard (0.10...0.78).contains(fill) else {
            trace("rejected: fill")
            return nil
        }

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
        guard support >= 0.45 else {
            trace("rejected: surround support \(String(format: "%.2f", support))")
            return nil
        }

        let mask = normalizedMask(
            for: component,
            localWidth: interior.width,
            gridWidth: 48,
            gridHeight: 24
        )
        guard let shape = classify(mask: mask, width: 48, height: 24) else {
            trace("rejected: shape did not classify as an arrow")
            return nil
        }
        trace("ACCEPTED as \(shape.direction)")

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

    /// Decides direction from the shape's thickness profile.
    ///
    /// Template matching was direction-blind here: a left arrow scored 0.726
    /// and a right arrow 0.711 on the same pixels, a margin too small to mean
    /// anything. What actually distinguishes an arrow is where the metal is.
    /// Along its length a shaft is thin and even; an arrowhead swells to a
    /// base and then tapers to a point at the very tip. Measuring that is both
    /// direction-discriminating and blunt-object rejecting, which is exactly
    /// the pair of decisions being made.
    private func classify(mask: [Bool], width: Int, height: Int) -> ShapeScore? {
        func note(_ text: String) {
            guard ArrowTrace.isOn else { return }
            FileHandle.standardError.write(Data("    classify: \(text)\n".utf8))
        }

        let symmetry = verticalSymmetry(of: mask, width: width, height: height)
        // Perspective, glare and mounting bolts remove a sizeable portion of
        // one half of arrows in field photos. Direction still requires the
        // independent tapered-head test below, so symmetry is only a weak
        // rejection gate rather than proof by itself.
        note("symmetry \(String(format: "%.3f", symmetry)) (needs 0.30)")
        guard symmetry >= 0.30 else { return nil }

        var thickness = [Float](repeating: 0, count: width)
        for x in 0..<width {
            var count = 0
            for y in 0..<height where mask[y * width + x] { count += 1 }
            thickness[x] = Float(count)
        }
        guard thickness.contains(where: { $0 > 0 }) else { return nil }

        let headSpan = max(2, width * 25 / 100)
        let tipSpan = max(1, width * 8 / 100)
        let middle = Array(thickness[(width * 40 / 100)..<(width * 60 / 100)])
        let shaft = middle.reduce(0, +) / Float(max(1, middle.count))
        guard shaft > 0 else { return nil }

        let leftBase = thickness[0..<headSpan].max() ?? 0
        let leftTip = thickness[0..<tipSpan].reduce(0, +) / Float(tipSpan)
        let rightBase = thickness[(width - headSpan)..<width].max() ?? 0
        let rightTip = thickness[(width - tipSpan)..<width].reduce(0, +) / Float(tipSpan)

        // A head is wider than the shaft it sits on and narrows to a point.
        // The taper is what separates an arrowhead from a squared-off end cap.
        func isHead(base: Float, tip: Float) -> Bool {
            base >= shaft * 1.5 && tip <= base * 0.65
        }

        let pointsLeft = isHead(base: leftBase, tip: leftTip)
        let pointsRight = isHead(base: rightBase, tip: rightTip)
        note("shaft \(String(format: "%.2f", shaft)) "
            + "left base \(String(format: "%.2f", leftBase)) tip \(String(format: "%.2f", leftTip)) -> \(pointsLeft) "
            + "right base \(String(format: "%.2f", rightBase)) tip \(String(format: "%.2f", rightTip)) -> \(pointsRight)")

        let direction: VisualDirection
        switch (pointsLeft, pointsRight) {
        case (true, true): direction = .bidirectional
        case (true, false): direction = .left
        case (false, true): direction = .right
        case (false, false): return nil
        }

        let swell = max(pointsLeft ? leftBase : 0, pointsRight ? rightBase : 0) / shaft
        let confidence = min(Float(1), (swell - 1) / 2)
        note("ACCEPTED \(direction) confidence \(String(format: "%.3f", confidence))")
        return ShapeScore(
            direction: direction,
            score: confidence * 0.75 + symmetry * 0.25
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
