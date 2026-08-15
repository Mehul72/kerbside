import CoreGraphics
import Foundation
import Vision

/// Finds physical sign plates before their words are assembled.
///
/// The first OCR pass only locates the pole. Rectangle detection then runs on
/// that much smaller crop, where a plate is large enough to distinguish from
/// a word, bolt, branch, or building. Text is never interpreted here; it is
/// used only as geometric evidence that a rectangle contains a sign face.
struct PanelFaceDetector {
    struct Detection {
        var regions: [PanelRegion]
        var scoutLines: [TextObservation]
    }

    func detect(
        in image: CGImage,
        seededBy seedLines: [TextObservation]
    ) throws -> Detection {
        guard !seedLines.isEmpty,
              let roi = signRegion(for: seedLines),
              let crop = ImageRegion.cropAndScale(image, normalized: roi)
        else { return Detection(regions: [], scoutLines: []) }

        let textRequest = configuredTextRequest()
        let rectangleRequest = VNDetectRectanglesRequest()
        rectangleRequest.maximumObservations = 64
        rectangleRequest.minimumConfidence = 0.2
        rectangleRequest.minimumSize = 0.06
        rectangleRequest.minimumAspectRatio = 0.1
        rectangleRequest.maximumAspectRatio = 1
        rectangleRequest.quadratureTolerance = 25

        try VNImageRequestHandler(cgImage: crop).perform([textRequest, rectangleRequest])

        var lines = (textRequest.results ?? []).compactMap { observation in
            observation.topCandidates(1).first.map { candidate in
                TextObservation(
                    text: candidate.string,
                    confidence: candidate.confidence,
                    boundingBox: global(observation.boundingBox, inside: roi)
                )
            }
        }
        let lineSamples = PanelColourSampler.samples(
            for: lines.map {
                $0.boundingBox.insetBy(
                    dx: -$0.boundingBox.width * 0.06,
                    dy: $0.boundingBox.height * 0.22
                )
            },
            in: image
        )
        lines = zip(lines, lineSamples).map { line, sample in
            TextObservation(
                text: line.text,
                confidence: line.confidence,
                boundingBox: line.boundingBox,
                colourHint: sample.hint
            )
        }

        let rawBoxes = (rectangleRequest.results ?? []).map {
            global($0.boundingBox, inside: roi)
        }
        let samples = PanelColourSampler.samples(for: rawBoxes, in: image)
        let candidates = zip(rectangleRequest.results ?? [], zip(rawBoxes, samples)).compactMap {
            rectangle, pair -> Candidate? in
            let (box, sample) = pair
            let local = local(box, inside: roi)
            let localArea = area(local)
            guard (0.015...0.45).contains(localArea),
                  local.width >= 0.10,
                  local.height >= 0.10
            else { return nil }

            let lineIndices = Set(lines.indices.filter { index in
                containsCenter(of: lines[index].boundingBox, in: box, tolerance: 0.008)
            })
            return Candidate(
                box: box,
                lineIndices: lineIndices,
                hint: resolvedHint(sample.hint, lineIndices: lineIndices, lines: lines),
                confidence: rectangle.confidence,
                cameFromRectangle: true
            )
        }

        var selected = selectRectangles(candidates, lines: lines, roi: roi)
        let derived = deriveFaces(
            from: lines,
            excluding: selected,
            inside: roi
        )
        for candidate in derived where !selected.contains(where: {
            representsSameFace($0, candidate)
        }) {
            selected.append(candidate)
        }
        selected = consolidate(selected, lines: lines)

        // A text-only grouping is still the old heuristic in a new coat. Use
        // this stage only when at least one physical rectangle anchored it.
        guard selected.contains(where: \.cameFromRectangle) else {
            return Detection(regions: [], scoutLines: lines)
        }

        let regions = selected
            .map { candidate in
                PanelRegion(
                    boundingBox: candidate.box,
                    colourHint: candidate.hint,
                    confidence: candidate.confidence
                )
            }
            .sorted(by: regionComesFirst)
        return Detection(regions: regions, scoutLines: lines)
    }

    private struct Candidate {
        var box: CGRect
        var lineIndices: Set<Int>
        var hint: PanelColourHint
        var confidence: Float
        var cameFromRectangle: Bool
    }

    private func signRegion(for lines: [TextObservation]) -> CGRect? {
        let coloured = lines.filter {
            $0.colourHint == .red || $0.colourHint == .green
        }
        let anchors = coloured.isEmpty ? lines : coloured
        guard var seed = union(of: anchors.map(\.boundingBox)) else { return nil }

        // Include nearby colourless text such as a sticker fixed to the same
        // pole, while leaving unrelated building text outside the crop.
        let neighbourhood = seed.insetBy(
            dx: -max(0.10, seed.width * 0.30),
            dy: -max(0.10, seed.height * 0.22)
        )
        let nearby = lines.filter { $0.boundingBox.intersects(neighbourhood) }
        if let nearbyUnion = union(of: nearby.map(\.boundingBox)) {
            seed = seed.union(nearbyUnion)
        }

        return seed.insetBy(
            dx: -max(0.04, seed.width * 0.12),
            dy: -max(0.04, seed.height * 0.08)
        )
        .intersection(unit)
    }

    private func selectRectangles(
        _ candidates: [Candidate],
        lines: [TextObservation],
        roi: CGRect
    ) -> [Candidate] {
        var selected: [Candidate] = []

        // Text-bearing or coloured rectangles establish the first trustworthy
        // faces. Larger duplicates win because Vision commonly traces both the
        // printed content and the enamel edge of the same plate.
        let anchored = candidates.filter { $0.lineIndices.count >= 2 }
        for candidate in anchored.sorted(by: largerCandidateFirst) {
            guard !selected.contains(where: {
                duplicateRectangle($0, candidate)
            }) else { continue }
            selected.append(candidate)
        }

        // A plate carrying only a symbol has no OCR anchor. Keep a large,
        // empty rectangle only when it sits beside a face that did have text;
        // this preserves an explicit unreadable result without promoting a
        // random window elsewhere in the photograph.
        let empty = candidates.filter {
            $0.lineIndices.isEmpty
                && area(local($0.box, inside: roi)) >= 0.05
                && isNearKnownFace($0.box, selected: selected)
        }
        for candidate in empty.sorted(by: largerCandidateFirst) {
            guard !selected.contains(where: {
                duplicateRectangle($0, candidate)
            }) else { continue }
            selected.append(candidate)
        }

        // Reject broad wrappers that contain several independently anchored
        // faces. They describe the pole, not one plate.
        return selected.filter { candidate in
            let children = selected.filter { other in
                area(other.box) < area(candidate.box) * 0.75
                    && containment(of: other.box, in: candidate.box) >= 0.9
                    && !other.lineIndices.isEmpty
            }
            let distinct = children.filter { child in
                !children.contains { other in
                    area(other.box) < area(child.box)
                        && containment(of: other.box, in: child.box) >= 0.9
                }
            }
            return distinct.count < 2
        }
    }

    /// Vision often traces the two printed halves of one wide plate as two
    /// rectangles. Join only similarly sized, horizontally adjacent pieces;
    /// a tall neighbouring plate must remain independent.
    private func consolidate(
        _ candidates: [Candidate],
        lines: [TextObservation]
    ) -> [Candidate] {
        var remaining = candidates
        var result: [Candidate] = []
        while !remaining.isEmpty {
            var current = remaining.removeFirst()
            var changed = true
            while changed {
                changed = false
                if let index = remaining.firstIndex(where: { other in
                    guard current.hint == other.hint,
                          current.hint == .red,
                          hasRestrictionText(current, lines: lines)
                            != hasRestrictionText(other, lines: lines)
                    else { return false }
                    let heightRatio = min(current.box.height, other.box.height)
                        / max(current.box.height, other.box.height)
                    let verticalOverlap = max(
                        0,
                        min(current.box.maxY, other.box.maxY)
                            - max(current.box.minY, other.box.minY)
                    ) / min(current.box.height, other.box.height)
                    let horizontalGap = max(
                        0,
                        max(current.box.minX, other.box.minX)
                            - min(current.box.maxX, other.box.maxX)
                    )
                    return heightRatio >= 0.65
                        && verticalOverlap >= 0.65
                        && horizontalGap <= 0.035
                }) {
                    let other = remaining.remove(at: index)
                    current.box = current.box.union(other.box)
                    current.lineIndices.formUnion(other.lineIndices)
                    current.confidence = max(current.confidence, other.confidence)
                    changed = true
                }
            }
            result.append(current)
        }
        return result
    }

    private func hasRestrictionText(
        _ candidate: Candidate,
        lines: [TextObservation]
    ) -> Bool {
        let text = candidate.lineIndices
            .map { lines[$0].text.uppercased() }
            .joined(separator: " ")
        return text.contains("NO STOP") || text.contains("NO PARK")
    }

    private func deriveFaces(
        from lines: [TextObservation],
        excluding selected: [Candidate],
        inside roi: CGRect
    ) -> [Candidate] {
        let unclaimed = lines.indices.filter { index in
            !selected.contains { candidate in
                containsCenter(
                    of: lines[index].boundingBox,
                    in: candidate.box,
                    tolerance: 0.012
                )
            }
        }
        guard unclaimed.count >= 2 else { return [] }

        var parent = Array(lines.indices)
        func root(_ index: Int) -> Int {
            var current = index
            while parent[current] != current { current = parent[current] }
            return current
        }

        for leftPosition in unclaimed.indices {
            let left = unclaimed[leftPosition]
            for rightPosition in unclaimed.indices where rightPosition > leftPosition {
                let right = unclaimed[rightPosition]
                guard compatible(lines[left], lines[right], inside: roi) else { continue }
                let leftRoot = root(left)
                let rightRoot = root(right)
                if leftRoot != rightRoot {
                    parent[max(leftRoot, rightRoot)] = min(leftRoot, rightRoot)
                }
            }
        }

        let groups = Dictionary(grouping: unclaimed, by: root)
        return groups.values.compactMap { indices in
            guard indices.count >= 2,
                  let lineUnion = union(of: indices.map { lines[$0].boundingBox })
            else { return nil }
            let localUnion = local(lineUnion, inside: roi)
            let expandedLocal = localUnion.insetBy(
                dx: -max(0.035, localUnion.width * 0.16),
                dy: -max(0.028, localUnion.height * 0.18)
            )
            .intersection(unit)
            let hint = majorityHint(indices.map { lines[$0].colourHint })
            return Candidate(
                box: global(expandedLocal, inside: roi),
                lineIndices: Set(indices),
                hint: hint,
                confidence: 0.5,
                cameFromRectangle: false
            )
        }
    }

    private func compatible(
        _ lhs: TextObservation,
        _ rhs: TextObservation,
        inside roi: CGRect
    ) -> Bool {
        if lhs.colourHint != rhs.colourHint,
           lhs.colourHint != .none,
           rhs.colourHint != .none,
           lhs.colourHint != .mixed,
           rhs.colourHint != .mixed {
            return false
        }
        let left = local(lhs.boundingBox, inside: roi)
        let right = local(rhs.boundingBox, inside: roi)
        let horizontalGap = max(left.minX, right.minX) - min(left.maxX, right.maxX)
        let verticalGap = max(left.minY, right.minY) - min(left.maxY, right.maxY)
        let overlap = max(0, min(left.maxX, right.maxX) - max(left.minX, right.minX))
        let smallerWidth = min(left.width, right.width)
        return verticalGap <= 0.13
            && (horizontalGap <= 0.045 || overlap >= smallerWidth * 0.18)
    }

    private func configuredTextRequest() -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        request.customWords = [
            "NO PARKING", "NO STOPPING", "TICKET", "METER",
            "MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN",
            "PUBLIC HOLIDAYS",
        ]
        request.minimumTextHeight = 0.01
        return request
    }

    private func resolvedHint(
        _ sampled: PanelColourHint,
        lineIndices: Set<Int>,
        lines: [TextObservation]
    ) -> PanelColourHint {
        let words = lineIndices.map { lines[$0].text.uppercased() }.joined(separator: " ")
        if words.contains("NO STOP") || words.contains("NO PARK") { return .red }
        if words.contains("METER")
            || words.range(of: #"\b\d+\s*P\b"#, options: .regularExpression) != nil {
            return .green
        }
        guard sampled == .none || sampled == .mixed else { return sampled }
        return majorityHint(lineIndices.map { lines[$0].colourHint })
    }

    private func majorityHint(_ hints: [PanelColourHint]) -> PanelColourHint {
        let red = hints.count { $0 == .red }
        let green = hints.count { $0 == .green }
        if red > green, red > 0 { return .red }
        if green > red, green > 0 { return .green }
        return .none
    }

    private func largerCandidateFirst(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        if area(lhs.box) != area(rhs.box) { return area(lhs.box) > area(rhs.box) }
        if lhs.confidence != rhs.confidence { return lhs.confidence > rhs.confidence }
        return regionComesFirst(
            PanelRegion(boundingBox: lhs.box),
            PanelRegion(boundingBox: rhs.box)
        )
    }

    private func duplicateRectangle(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        let sharedLines = !lhs.lineIndices.isEmpty
            && lhs.lineIndices == rhs.lineIndices
        let nestedEmpty = lhs.lineIndices.isEmpty
            && rhs.lineIndices.isEmpty
            && (containment(of: lhs.box, in: rhs.box) >= 0.85
                || containment(of: rhs.box, in: lhs.box) >= 0.85)
        return (sharedLines || nestedEmpty)
            && overlapOfSmaller(lhs.box, rhs.box) >= 0.7
    }

    private func representsSameFace(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        guard lhs.hint == rhs.hint || lhs.hint == .none || rhs.hint == .none else {
            return false
        }
        return intersectionOverUnion(lhs.box, rhs.box) >= 0.45
            || overlapOfSmaller(lhs.box, rhs.box) >= 0.78
    }

    private func isNearKnownFace(_ box: CGRect, selected: [Candidate]) -> Bool {
        selected.contains { candidate in
            let horizontalGap = max(box.minX, candidate.box.minX)
                - min(box.maxX, candidate.box.maxX)
            let verticalOverlap = max(
                0,
                min(box.maxY, candidate.box.maxY) - max(box.minY, candidate.box.minY)
            )
            return horizontalGap <= max(0.035, min(box.width, candidate.box.width) * 0.35)
                && verticalOverlap >= min(box.height, candidate.box.height) * 0.25
        }
    }

    private func regionComesFirst(_ lhs: PanelRegion, _ rhs: PanelRegion) -> Bool {
        if lhs.boundingBox.maxY != rhs.boundingBox.maxY {
            return lhs.boundingBox.maxY > rhs.boundingBox.maxY
        }
        if lhs.boundingBox.minX != rhs.boundingBox.minX {
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }
        return area(lhs.boundingBox) > area(rhs.boundingBox)
    }

    private func containsCenter(
        of inner: CGRect,
        in outer: CGRect,
        tolerance: CGFloat
    ) -> Bool {
        outer.insetBy(dx: -tolerance, dy: -tolerance).contains(
            CGPoint(x: inner.midX, y: inner.midY)
        )
    }

    private func containment(of inner: CGRect, in outer: CGRect) -> CGFloat {
        let intersection = inner.intersection(outer)
        guard !intersection.isNull, !intersection.isEmpty, area(inner) > 0 else { return 0 }
        return area(intersection) / area(inner)
    }

    private func overlapOfSmaller(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull, !intersection.isEmpty else { return 0 }
        let smaller = min(area(lhs), area(rhs))
        guard smaller > 0 else { return 0 }
        return area(intersection) / smaller
    }

    private func intersectionOverUnion(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull, !intersection.isEmpty else { return 0 }
        let unionArea = area(lhs) + area(rhs) - area(intersection)
        guard unionArea > 0 else { return 0 }
        return area(intersection) / unionArea
    }

    private func union(of rectangles: [CGRect]) -> CGRect? {
        guard let first = rectangles.first else { return nil }
        return rectangles.dropFirst().reduce(first) { $0.union($1) }
    }

    private func global(_ local: CGRect, inside roi: CGRect) -> CGRect {
        CGRect(
            x: roi.minX + local.minX * roi.width,
            y: roi.minY + local.minY * roi.height,
            width: local.width * roi.width,
            height: local.height * roi.height
        )
    }

    private func local(_ global: CGRect, inside roi: CGRect) -> CGRect {
        CGRect(
            x: (global.minX - roi.minX) / roi.width,
            y: (global.minY - roi.minY) / roi.height,
            width: global.width / roi.width,
            height: global.height / roi.height
        )
    }

    private func area(_ rectangle: CGRect) -> CGFloat {
        rectangle.width * rectangle.height
    }

    private var unit: CGRect {
        CGRect(x: 0, y: 0, width: 1, height: 1)
    }
}

enum ImageRegion {
    static func cropAndScale(
        _ image: CGImage,
        normalized box: CGRect,
        minimumLongestEdge: CGFloat = 1_200,
        maximumScale: CGFloat = 5
    ) -> CGImage? {
        let clipped = box.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !clipped.isNull, !clipped.isEmpty else { return nil }
        let pixels = CGRect(
            x: clipped.minX * CGFloat(image.width),
            y: (1 - clipped.maxY) * CGFloat(image.height),
            width: clipped.width * CGFloat(image.width),
            height: clipped.height * CGFloat(image.height)
        ).integral
        guard pixels.width >= 2, pixels.height >= 2,
              let cropped = image.cropping(to: pixels)
        else { return nil }

        let longest = CGFloat(max(cropped.width, cropped.height))
        let scale = min(maximumScale, max(1, minimumLongestEdge / longest))
        guard scale > 1 else { return cropped }
        let width = max(1, Int((CGFloat(cropped.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(cropped.height) * scale).rounded()))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
