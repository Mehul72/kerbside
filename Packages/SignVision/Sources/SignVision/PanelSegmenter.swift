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
            return unreadableBlocks(
                in: canonicalRegions,
                excludingLines: [],
                claimedRegionIndices: []
            )
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
        let claimedRegionIndices = Set(assigned.compactMap(\.regionIndex))

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
            let lineBounds = groupLines.dropFirst().reduce(groupLines[0].boundingBox) {
                $0.union($1.boundingBox)
            }
            return PanelBlock(
                rawText: groupLines.map(\.text).joined(separator: "\n"),
                lines: groupLines,
                boundingBox: region?.boundingBox ?? lineBounds,
                colourHint: region?.colourHint ?? .none,
                sourceRegion: region
            )
        }
        blocks.append(
            contentsOf: unreadableBlocks(
                in: canonicalRegions,
                excludingLines: lines,
                claimedRegionIndices: claimedRegionIndices
            )
        )
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
            let region = regions[index].boundingBox.insetBy(dx: -0.005, dy: -0.005)
            return region.contains(center)
                && regions[index].boundingBox.height >= line.boundingBox.height * 1.4
                && regions[index].boundingBox.width >= line.boundingBox.width * 0.75
        }
        guard !candidates.isEmpty else { return nil }

        // Rectangles cut from one solid face share a connected-colour ID even
        // when Vision finds separate boxes around each word or arrow. Resolve
        // that component to one stable representative before grouping lines.
        let componentCandidates = Dictionary(grouping: candidates) { index in
            regions[index].colourEvidence.componentID
        }
        .compactMap { componentID, members -> (
            id: Int,
            members: [Int],
            minimumArea: CGFloat,
            score: Float
        )? in
            guard let componentID else { return nil }
            let strongMembers = members.filter {
                regions[$0].colourEvidence.supportsStandalonePanel
            }
            guard !strongMembers.isEmpty else { return nil }
            let minimumArea = strongMembers.map {
                area(regions[$0].boundingBox)
            }.min() ?? 0
            let score = strongMembers.map {
                regions[$0].colourEvidence.standaloneScore
            }.max() ?? 0
            return (componentID, strongMembers, minimumArea, score)
        }
        .sorted { lhs, rhs in
            if lhs.minimumArea != rhs.minimumArea {
                return lhs.minimumArea < rhs.minimumArea
            }
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.id < rhs.id
        }
        if let component = componentCandidates.first {
            return component.members
                .sorted { lhs, rhs in
                    let lhsArea = area(regions[lhs].boundingBox)
                    let rhsArea = area(regions[rhs].boundingBox)
                    if lhsArea != rhsArea { return lhsArea < rhsArea }
                    let lhsScore = regions[lhs].colourEvidence.standaloneScore
                    let rhsScore = regions[rhs].colourEvidence.standaloneScore
                    if lhsScore != rhsScore { return lhsScore > rhsScore }
                    return lhs < rhs
                }
                .first
        }

        // Only boundary-backed colour evidence is allowed to establish a
        // physical face. A broad wrapper or an internal arrow may contain red
        // or green pixels, but it does not have a separate four-edge boundary.
        let colouredFaces = candidates.filter { index in
            regions[index].colourHint != .none
                && regions[index].colourEvidence.supportsStandalonePanel
        }
        if let face = colouredFaces.sorted(by: { lhs, rhs in
            let lhsScore = regions[lhs].colourEvidence.standaloneScore
            let rhsScore = regions[rhs].colourEvidence.standaloneScore
            if lhsScore != rhsScore { return lhsScore > rhsScore }
            let lhsArea = area(regions[lhs].boundingBox)
            let rhsArea = area(regions[rhs].boundingBox)
            if lhsArea != rhsArea { return lhsArea < rhsArea }
            return lhs < rhs
        }).first {
            return face
        }

        // Without colour evidence, the smallest containing rectangle is the
        // least likely to bridge two adjacent panels.
        return candidates.min(by: {
            area(regions[$0].boundingBox) < area(regions[$1].boundingBox)
        })
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

    /// A coloured sign rectangle with no OCR line is still a panel result.
    /// Vision often returns shifted, partly overlapping rectangles for one
    /// face, border, word, or arrow, so exact containment is not sufficient.
    private func unreadableBlocks(
        in regions: [PanelRegion],
        excludingLines lines: [TextObservation],
        claimedRegionIndices: Set<Int>
    ) -> [PanelBlock] {
        let regionsWithText = Set(regions.indices.filter { index in
            lines.contains { line in intersects(line, regions[index].boundingBox) }
        })

        let candidates = regions.indices.filter { index in
            guard regions[index].colourHint != .none else { return false }
            guard regions[index].colourEvidence.supportsStandalonePanel else { return false }
            guard !regionsWithText.contains(index) else { return false }
            return !claimedRegionIndices.contains { claimedIndex in
                guard regions[claimedIndex].colourEvidence.supportsStandalonePanel else {
                    return false
                }
                return representsSamePanel(regions[index], regions[claimedIndex])
            }
        }

        return deduplicatedCandidates(candidates, in: regions).map { index in
            let region = regions[index]
            return PanelBlock(
                rawText: "",
                lines: [],
                boundingBox: region.boundingBox,
                colourHint: region.colourHint,
                sourceRegion: region
            )
        }
    }

    /// Builds overlap clusters from smaller rectangles first. A later wrapper
    /// that bridges multiple existing clusters is ignored rather than merging
    /// two genuine panels into one.
    private func deduplicatedCandidates(
        _ candidates: [Int],
        in regions: [PanelRegion]
    ) -> [Int] {
        let ordered = candidates.sorted { lhs, rhs in
            let lhsArea = area(regions[lhs].boundingBox)
            let rhsArea = area(regions[rhs].boundingBox)
            if lhsArea != rhsArea { return lhsArea < rhsArea }
            return lhs < rhs
        }
        var clusters: [[Int]] = []

        for candidate in ordered {
            let matchingClusters = clusters.indices.filter { clusterIndex in
                clusters[clusterIndex].contains { member in
                    representsSamePanel(regions[candidate], regions[member])
                }
            }

            if matchingClusters.isEmpty {
                clusters.append([candidate])
            } else if matchingClusters.count == 1,
                      let clusterIndex = matchingClusters.first {
                clusters[clusterIndex].append(candidate)
            }
        }

        return clusters.compactMap { cluster in
            cluster.sorted { lhs, rhs in
                let lhsScore = regions[lhs].colourEvidence.standaloneScore
                let rhsScore = regions[rhs].colourEvidence.standaloneScore
                if lhsScore != rhsScore { return lhsScore > rhsScore }
                if regions[lhs].confidence != regions[rhs].confidence {
                    return regions[lhs].confidence > regions[rhs].confidence
                }
                let lhsArea = area(regions[lhs].boundingBox)
                let rhsArea = area(regions[rhs].boundingBox)
                if lhsArea != rhsArea { return lhsArea > rhsArea }
                return lhs < rhs
            }.first
        }
        .sorted { regionComesFirst(regions[$0], regions[$1]) }
    }

    private func representsSamePanel(_ lhs: PanelRegion, _ rhs: PanelRegion) -> Bool {
        if lhs.colourEvidence.supportsStandalonePanel,
           rhs.colourEvidence.supportsStandalonePanel,
           lhs.colourEvidence.componentID != nil,
           rhs.colourEvidence.componentID != nil {
            return intersectionOverUnion(lhs.boundingBox, rhs.boundingBox) >= 0.6
        }

        if stronglyOverlaps(lhs.boundingBox, rhs.boundingBox) { return true }

        guard lhs.colourEvidence.componentID == rhs.colourEvidence.componentID,
              lhs.colourEvidence.componentID != nil
        else { return false }

        // A shared component can absorb a weak internal observation, but two
        // independently bounded faces remain distinct even when downsampling
        // joins them with a one-pixel colour bridge.
        return !lhs.colourEvidence.supportsStandalonePanel
            || !rhs.colourEvidence.supportsStandalonePanel
    }

    private func stronglyOverlaps(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull, !intersection.isEmpty else { return false }
        let smallerArea = min(area(lhs), area(rhs))
        guard smallerArea > 0 else { return false }
        return area(intersection) / smallerArea >= 0.7
    }

    private func intersectionOverUnion(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull, !intersection.isEmpty else { return 0 }
        let unionArea = area(lhs) + area(rhs) - area(intersection)
        guard unionArea > 0 else { return 0 }
        return area(intersection) / unionArea
    }

    private func contains(_ line: TextObservation, in region: CGRect) -> Bool {
        region.insetBy(dx: -0.015, dy: -0.015).contains(
            CGPoint(x: line.boundingBox.midX, y: line.boundingBox.midY)
        )
    }

    private func intersects(_ line: TextObservation, _ region: CGRect) -> Bool {
        if contains(line, in: region) { return true }
        let intersection = line.boundingBox.intersection(region)
        guard !intersection.isNull, !intersection.isEmpty else { return false }
        let lineArea = area(line.boundingBox)
        return lineArea > 0 && area(intersection) / lineArea >= 0.25
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
