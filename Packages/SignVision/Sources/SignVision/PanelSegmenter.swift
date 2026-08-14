import CoreGraphics
import Foundation

/// Groups OCR lines into physical panels without interpreting their words.
///
/// Rectangle and colour observations win when available. Lines outside a
/// detected rectangle fall back to stable geometric grouping by vertical gap.
public struct PanelSegmenter: Sendable {
    public var minimumTextConfidence: Float

    public init(minimumTextConfidence: Float = 0.25) {
        self.minimumTextConfidence = minimumTextConfidence
    }

    public func segment(
        _ observations: [TextObservation],
        regions: [PanelRegion] = []
    ) -> [PanelBlock] {
        let lines = observations
            .compactMap(clean)
            .sorted(by: lineComesFirst)
        let canonicalRegions = regions
            .filter { $0.confidence >= 0.25 && !$0.boundingBox.isEmpty }
            .sorted(by: regionComesFirst)
        guard !lines.isEmpty else {
            return unreadableBlocks(in: canonicalRegions, excludingLines: [])
        }
        let medianHeight = median(lines.map { $0.boundingBox.height })

        struct AssignedLine {
            var line: TextObservation
            var regionIndex: Int?
        }

        let assigned = lines.map { line in
            AssignedLine(
                line: line,
                regionIndex: bestRegion(for: line, in: canonicalRegions)
            )
        }

        var groups: [[AssignedLine]] = []
        var current: [AssignedLine] = []

        for item in assigned {
            if let previous = current.last,
               shouldSplit(
                   previousLine: previous.line,
                   previousRegion: previous.regionIndex,
                   currentLine: item.line,
                   currentRegion: item.regionIndex,
                   medianHeight: medianHeight
               ) {
                groups.append(current)
                current = []
            }
            current.append(item)
        }
        if !current.isEmpty { groups.append(current) }

        var blocks = groups.map { group in
            let groupLines = group.map(\.line)
            let regionIndices = Set(group.compactMap(\.regionIndex))
            let region = regionIndices.count == 1
                ? canonicalRegions[regionIndices.first!]
                : nil
            return PanelBlock(
                rawText: groupLines.map(\.text).joined(separator: "\n"),
                lines: groupLines,
                boundingBox: groupLines.dropFirst().reduce(groupLines[0].boundingBox) {
                    $0.union($1.boundingBox)
                },
                colourHint: region?.colourHint ?? .none
            )
        }
        blocks.append(contentsOf: unreadableBlocks(in: canonicalRegions, excludingLines: lines))
        return blocks.sorted(by: blockComesFirst)
    }

    private func clean(_ observation: TextObservation) -> TextObservation? {
        guard observation.confidence >= minimumTextConfidence else { return nil }
        let text = observation.text
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard !text.isEmpty, !observation.boundingBox.isEmpty else { return nil }
        return TextObservation(
            text: text,
            confidence: observation.confidence,
            boundingBox: observation.boundingBox
        )
    }

    private func bestRegion(for line: TextObservation, in regions: [PanelRegion]) -> Int? {
        let center = CGPoint(x: line.boundingBox.midX, y: line.boundingBox.midY)
        let candidates = regions.indices.filter { index in
            let region = regions[index].boundingBox.insetBy(dx: -0.015, dy: -0.015)
            return region.contains(center)
                && regions[index].boundingBox.height >= line.boundingBox.height * 1.4
                && regions[index].boundingBox.width >= line.boundingBox.width * 0.75
        }
        guard let smallestArea = candidates.map({ area(regions[$0].boundingBox) }).min() else {
            return nil
        }

        // When nested rectangles are nearly the same size, a red/green signal
        // breaks the tie. A much larger coloured rectangle never swallows a
        // smaller panel merely because it had saturated pixels.
        return candidates
            .filter { area(regions[$0].boundingBox) <= smallestArea * 1.2 }
            .sorted { lhs, rhs in
                let lhsColourless = regions[lhs].colourHint == .none
                let rhsColourless = regions[rhs].colourHint == .none
                if lhsColourless != rhsColourless { return !lhsColourless }
                return area(regions[lhs].boundingBox) < area(regions[rhs].boundingBox)
            }
            .first
    }

    private func shouldSplit(
        previousLine: TextObservation,
        previousRegion: Int?,
        currentLine: TextObservation,
        currentRegion: Int?,
        medianHeight: CGFloat
    ) -> Bool {
        if let previousRegion, let currentRegion {
            return previousRegion != currentRegion
        }

        let verticalGap = previousLine.boundingBox.minY - currentLine.boundingBox.maxY
        let largeGap = verticalGap > max(0.025, medianHeight * 1.45)
        guard largeGap else { return false }

        return true
    }

    private func lineComesFirst(_ lhs: TextObservation, _ rhs: TextObservation) -> Bool {
        if lhs.boundingBox.maxY != rhs.boundingBox.maxY {
            return lhs.boundingBox.maxY > rhs.boundingBox.maxY
        }
        if lhs.boundingBox.minX != rhs.boundingBox.minX {
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }
        return lhs.text < rhs.text
    }

    /// A coloured sign rectangle with no OCR line is still a panel result. Only
    /// the smallest nested coloured rectangle is retained to avoid duplicates.
    private func unreadableBlocks(
        in regions: [PanelRegion],
        excludingLines lines: [TextObservation]
    ) -> [PanelBlock] {
        regions.indices.compactMap { index in
            let region = regions[index]
            guard region.colourHint != .none else { return nil }
            let containsText = lines.contains { line in
                region.boundingBox.insetBy(dx: -0.015, dy: -0.015).contains(
                    CGPoint(x: line.boundingBox.midX, y: line.boundingBox.midY)
                )
            }
            guard !containsText else { return nil }

            let containsSmallerColouredRegion = regions.indices.contains { otherIndex in
                guard otherIndex != index, regions[otherIndex].colourHint != .none else {
                    return false
                }
                let other = regions[otherIndex].boundingBox
                return area(other) < area(region.boundingBox) * 0.9
                    && region.boundingBox.contains(CGPoint(x: other.midX, y: other.midY))
            }
            guard !containsSmallerColouredRegion else { return nil }
            return PanelBlock(
                rawText: "",
                lines: [],
                boundingBox: region.boundingBox,
                colourHint: region.colourHint
            )
        }
    }

    private func blockComesFirst(_ lhs: PanelBlock, _ rhs: PanelBlock) -> Bool {
        if lhs.boundingBox.maxY != rhs.boundingBox.maxY {
            return lhs.boundingBox.maxY > rhs.boundingBox.maxY
        }
        if lhs.boundingBox.minX != rhs.boundingBox.minX {
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }
        return lhs.rawText < rhs.rawText
    }

    private func regionComesFirst(_ lhs: PanelRegion, _ rhs: PanelRegion) -> Bool {
        if lhs.boundingBox.maxY != rhs.boundingBox.maxY {
            return lhs.boundingBox.maxY > rhs.boundingBox.maxY
        }
        if lhs.boundingBox.minX != rhs.boundingBox.minX {
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }
        if area(lhs.boundingBox) != area(rhs.boundingBox) {
            return area(lhs.boundingBox) < area(rhs.boundingBox)
        }
        return lhs.colourHint.rawValue < rhs.colourHint.rawValue
    }

    private func area(_ rectangle: CGRect) -> CGFloat {
        rectangle.width * rectangle.height
    }

    private func median(_ values: [CGFloat]) -> CGFloat {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}
