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
}
