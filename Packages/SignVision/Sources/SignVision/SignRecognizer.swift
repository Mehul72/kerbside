import CoreGraphics
import Foundation
import ImageIO
import SignKit
import Vision

public enum SignVisionError: Error, Hashable, Sendable, LocalizedError {
    case imagePreparationFailed
    case noTextFound

    public var errorDescription: String? {
        switch self {
        case .imagePreparationFailed:
            "The photograph could not be prepared for reading."
        case .noTextFound:
            "No sign text was found in the photograph."
        }
    }
}

/// Runs Apple's on-device Vision requests and hands segmented text to SignKit.
public struct SignRecognizer: Sendable {
    public var segmenter: PanelSegmenter

    public init(segmenter: PanelSegmenter = PanelSegmenter()) {
        self.segmenter = segmenter
    }

    public func read(
        _ image: CGImage,
        orientation: CGImagePropertyOrientation = .up
    ) async throws -> SignReading {
        try await Task.detached(priority: .userInitiated) {
            try readSynchronously(image, orientation: orientation)
        }.value
    }

    private func readSynchronously(
        _ image: CGImage,
        orientation: CGImagePropertyOrientation
    ) throws -> SignReading {
        guard let prepared = ImagePreprocessor.prepare(image, orientation: orientation) else {
            throw SignVisionError.imagePreparationFailed
        }

        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = false
        textRequest.recognitionLanguages = ["en-US"]
        textRequest.customWords = [
            "NO PARKING", "NO STOPPING", "TICKET", "METER",
            "MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN",
            "PUBLIC HOLIDAYS",
        ]
        textRequest.minimumTextHeight = 0.008

        let rectangleRequest = VNDetectRectanglesRequest()
        rectangleRequest.maximumObservations = 32
        rectangleRequest.minimumConfidence = 0.3
        rectangleRequest.minimumSize = 0.05
        rectangleRequest.minimumAspectRatio = 0.1
        rectangleRequest.maximumAspectRatio = 1
        rectangleRequest.quadratureTolerance = 35

        let handler = VNImageRequestHandler(cgImage: prepared, orientation: .up)
        try handler.perform([textRequest, rectangleRequest])

        let recognised = (textRequest.results ?? []).compactMap { observation in
            observation.topCandidates(1).first.map { candidate in
                TextObservation(
                    text: candidate.string,
                    confidence: candidate.confidence,
                    boundingBox: observation.boundingBox
                )
            }
        }
        // The plate colour immediately around each line. On a pole where no
        // rectangle is found, a red line followed by a green one is the
        // clearest evidence that two different signs are being read.
        let lineColours = PanelColourSampler.samples(
            // Narrowed vertically and widened sideways. A line sitting at the
            // bottom edge of one plate would otherwise sample the plate below
            // it too and come back mixed, which is exactly the boundary the
            // colour is needed to find.
            for: recognised.map {
                $0.boundingBox.insetBy(dx: -$0.boundingBox.width * 0.06, dy: $0.boundingBox.height * 0.22)
            },
            in: prepared
        )
        let observations = zip(recognised, lineColours).map { line, sample in
            TextObservation(
                text: line.text,
                confidence: line.confidence,
                boundingBox: line.boundingBox,
                colourHint: sample.hint
            )
        }

        let plateDetection = try PanelFaceDetector().detect(
            in: prepared,
            seededBy: observations
        )
        if !plateDetection.regions.isEmpty {
            let segmentedBlocks = try blocksForDetectedFaces(
                plateDetection.regions,
                in: prepared
            )
            let blocks = PanelArrowDetector.annotate(
                segmentedBlocks,
                regions: plateDetection.regions,
                in: prepared
            )
            guard !blocks.isEmpty else { throw SignVisionError.noTextFound }
            return SignReading(
                sign: SignVision.assemble(blocks),
                blocks: blocks,
                regions: plateDetection.regions,
                pipelineVersion: SignVision.pipelineVersion
            )
        }

        let rectangles = (rectangleRequest.results ?? []).map(\.boundingBox)
        let colourSamples = PanelColourSampler.samples(for: rectangles, in: prepared)
        let regions = zip(rectangleRequest.results ?? [], colourSamples).map { rectangle, sample in
            PanelRegion(
                boundingBox: rectangle.boundingBox,
                colourHint: sample.hint,
                colourEvidence: sample.evidence,
                confidence: rectangle.confidence
            )
        }
        let segmentedBlocks = segmenter.segment(observations, regions: regions)
        let blocks = PanelArrowDetector.annotate(
            segmentedBlocks,
            regions: regions,
            in: prepared
        )
        guard !blocks.isEmpty else { throw SignVisionError.noTextFound }

        return SignReading(
            sign: SignVision.assemble(blocks),
            blocks: blocks,
            regions: regions,
            pipelineVersion: SignVision.pipelineVersion
        )
    }

    private func blocksForDetectedFaces(
        _ regions: [PanelRegion],
        in image: CGImage
    ) throws -> [PanelBlock] {
        try regions.compactMap { region in
            let face = region.boundingBox
            guard let crop = ImageRegion.cropAndScale(
                image,
                normalized: face,
                minimumLongestEdge: 1_000,
                maximumScale: 6
            ) else { return nil }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["en-US"]
            request.customWords = [
                "NO PARKING", "NO STOPPING", "TICKET", "METER",
                "MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN",
                "PUBLIC HOLIDAYS",
            ]
            request.minimumTextHeight = 0.012
            try VNImageRequestHandler(cgImage: crop).perform([request])

            let nestedFaces = regions.map(\.boundingBox).filter { other in
                other != face
                    && area(other) < area(face) * 0.72
                    && containment(of: other, in: face) >= 0.9
            }
            let lines = (request.results ?? []).compactMap { observation in
                observation.topCandidates(1).first.map { candidate in
                    TextObservation(
                        text: candidate.string,
                        confidence: candidate.confidence,
                        boundingBox: CGRect(
                            x: face.minX + observation.boundingBox.minX * face.width,
                            y: face.minY + observation.boundingBox.minY * face.height,
                            width: observation.boundingBox.width * face.width,
                            height: observation.boundingBox.height * face.height
                        ),
                        colourHint: region.colourHint
                    )
                }
            }
            .filter { line in
                !nestedFaces.contains { nested in
                    nested.contains(CGPoint(
                        x: line.boundingBox.midX,
                        y: line.boundingBox.midY
                    ))
                }
            }
            .sorted(by: textLineComesFirst)

            return PanelBlock(
                rawText: lines.map(\.text).joined(separator: "\n"),
                lines: lines,
                boundingBox: face,
                colourHint: region.colourHint,
                sourceRegion: region
            )
        }
    }

    private func textLineComesFirst(
        _ lhs: TextObservation,
        _ rhs: TextObservation
    ) -> Bool {
        let rowTolerance = max(lhs.boundingBox.height, rhs.boundingBox.height) * 0.55
        if abs(lhs.boundingBox.midY - rhs.boundingBox.midY) > rowTolerance {
            return lhs.boundingBox.midY > rhs.boundingBox.midY
        }
        return lhs.boundingBox.minX < rhs.boundingBox.minX
    }

    private func containment(of inner: CGRect, in outer: CGRect) -> CGFloat {
        let intersection = inner.intersection(outer)
        guard !intersection.isNull, !intersection.isEmpty, area(inner) > 0 else { return 0 }
        return area(intersection) / area(inner)
    }

    private func area(_ rectangle: CGRect) -> CGFloat {
        rectangle.width * rectangle.height
    }
}
