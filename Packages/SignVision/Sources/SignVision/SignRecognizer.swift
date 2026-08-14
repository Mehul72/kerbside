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

        let observations = (textRequest.results ?? []).compactMap { observation in
            observation.topCandidates(1).first.map { candidate in
                TextObservation(
                    text: candidate.string,
                    confidence: candidate.confidence,
                    boundingBox: observation.boundingBox
                )
            }
        }
        guard !observations.isEmpty else { throw SignVisionError.noTextFound }

        let rectangles = (rectangleRequest.results ?? []).map(\.boundingBox)
        let colourHints = PanelColourSampler.hints(for: rectangles, in: prepared)
        let regions = zip(rectangleRequest.results ?? [], colourHints).map { rectangle, colour in
            PanelRegion(
                boundingBox: rectangle.boundingBox,
                colourHint: colour,
                confidence: rectangle.confidence
            )
        }
        let blocks = segmenter.segment(observations, regions: regions)
        guard !blocks.isEmpty else { throw SignVisionError.noTextFound }

        return SignReading(
            sign: SignVision.assemble(blocks),
            blocks: blocks,
            pipelineVersion: SignVision.pipelineVersion
        )
    }
}
