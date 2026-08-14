import CoreGraphics
import CoreText
import Foundation
import SignKit
import Testing

@testable import SignVision

struct PanelSegmenterTests {
    @Test("geometry splits panels and preserves top-to-bottom line order")
    func geometry() {
        let observations = [
            line("MON - FRI", y: 0.59),
            line("NO STOPPING", y: 0.90),
            line("1P", y: 0.66),
            line("8AM - 6PM", y: 0.62),
        ]

        let blocks = PanelSegmenter().segment(observations)

        #expect(blocks.map(\.rawText) == ["NO STOPPING", "1P\n8AM - 6PM\nMON - FRI"])
    }

    @Test("detected rectangles split panels even when their text is close")
    func rectangles() {
        let observations = [
            line("NO PARKING", y: 0.70),
            line("1P", y: 0.65),
        ]
        let regions = [
            PanelRegion(
                boundingBox: CGRect(x: 0.1, y: 0.68, width: 0.8, height: 0.08),
                colourHint: .red
            ),
            PanelRegion(
                boundingBox: CGRect(x: 0.1, y: 0.61, width: 0.8, height: 0.07),
                colourHint: .green
            ),
        ]

        let blocks = PanelSegmenter().segment(observations, regions: regions)

        #expect(blocks.map(\.rawText) == ["NO PARKING", "1P"])
        #expect(blocks.map(\.colourHint) == [.red, .green])
    }

    @Test("one detected panel keeps its lines together across a large gap")
    func rectangleKeepsPanelTogether() {
        let observations = [
            line("NO PARKING", y: 0.80),
            line("MON - FRI", y: 0.55),
        ]
        let region = PanelRegion(
            boundingBox: CGRect(x: 0.1, y: 0.50, width: 0.8, height: 0.36),
            colourHint: .red
        )

        let blocks = PanelSegmenter().segment(observations, regions: [region])

        #expect(blocks.map(\.rawText) == ["NO PARKING\nMON - FRI"])
    }

    @Test("red and green pixels are only reported as panel hints")
    func colourHints() throws {
        let image = try #require(Self.twoColourImage())
        let hints = PanelColourSampler.hints(
            for: [
                CGRect(x: 0, y: 0.5, width: 1, height: 0.5),
                CGRect(x: 0, y: 0, width: 1, height: 0.5),
            ],
            in: image
        )

        #expect(hints == [.red, .green])
    }

    @Test("localized colour and brown branches are not sign evidence")
    func colourNoise() throws {
        let localizedRed = try #require(Self.localizedRedImage())
        let brown = try #require(
            Self.solidImage(
                width: 100,
                height: 100,
                colour: CGColor(red: 0.55, green: 0.38, blue: 0.22, alpha: 1)
            )
        )

        let region = CGRect(x: 0, y: 0, width: 1, height: 1)
        let localizedSample = try #require(
            PanelColourSampler.samples(for: [region], in: localizedRed).first
        )
        let brownSample = try #require(
            PanelColourSampler.samples(for: [region], in: brown).first
        )

        #expect(localizedSample.hint == .red)
        #expect(!localizedSample.evidence.supportsStandalonePanel)
        #expect(brownSample.hint == .none)
        #expect(!brownSample.evidence.supportsStandalonePanel)
    }

    @Test("distributed red and green borders remain sign evidence")
    func colourBorders() throws {
        let red = try #require(Self.borderImage(colour: .red))
        let green = try #require(Self.borderImage(colour: .green))
        let darkRed = try #require(Self.borderImage(colour: .red, dark: true))
        let darkGreen = try #require(Self.borderImage(colour: .green, dark: true))
        let region = CGRect(
            x: 20.0 / 240.0,
            y: 20.0 / 240.0,
            width: 200.0 / 240.0,
            height: 200.0 / 240.0
        )

        let redSample = try #require(PanelColourSampler.samples(for: [region], in: red).first)
        let greenSample = try #require(
            PanelColourSampler.samples(for: [region], in: green).first
        )
        let darkRedSample = try #require(
            PanelColourSampler.samples(for: [region], in: darkRed).first
        )
        let darkGreenSample = try #require(
            PanelColourSampler.samples(for: [region], in: darkGreen).first
        )

        #expect(redSample.hint == .red)
        #expect(redSample.evidence.supportsStandalonePanel)
        #expect(greenSample.hint == .green)
        #expect(greenSample.evidence.supportsStandalonePanel)
        #expect(darkRedSample.evidence.supportsStandalonePanel)
        #expect(darkGreenSample.evidence.supportsStandalonePanel)
    }

    @Test("an image-edge rectangle has no standalone boundary")
    func fullFrameColour() throws {
        let image = try #require(
            Self.solidImage(
                width: 200,
                height: 200,
                colour: CGColor(red: 0.9, green: 0, blue: 0, alpha: 1)
            )
        )
        let sample = try #require(
            PanelColourSampler.samples(
                for: [CGRect(x: 0, y: 0, width: 1, height: 1)],
                in: image
            ).first
        )

        #expect(sample.hint == .red)
        #expect(!sample.evidence.supportsStandalonePanel)
    }

    @Test("one colour component collapses internal rectangles")
    func sampledSinglePanel() throws {
        let image = try #require(Self.colouredPanelImage(stacked: false))
        let boxes = [
            CGRect(x: 0.20, y: 0.10, width: 0.60, height: 0.80),
            CGRect(x: 0.25, y: 0.65, width: 0.20, height: 0.10),
            CGRect(x: 0.55, y: 0.25, width: 0.20, height: 0.10),
        ]
        let samples = PanelColourSampler.samples(for: boxes, in: image)
        let regions = zip(boxes, samples).map { box, sample in
            PanelRegion(
                boundingBox: box,
                colourHint: sample.hint,
                colourEvidence: sample.evidence
            )
        }

        #expect(samples[0].evidence.supportsStandalonePanel)
        #expect(!samples[1].evidence.supportsStandalonePanel)
        #expect(!samples[2].evidence.supportsStandalonePanel)
        #expect(Set(samples.compactMap(\.evidence.componentID)).count == 1)
        #expect(PanelSegmenter().segment([], regions: regions).count == 1)
    }

    @Test("separate colour components preserve stacked panels")
    func sampledStackedPanels() throws {
        let image = try #require(Self.colouredPanelImage(stacked: true))
        let boxes = [
            CGRect(x: 0.15, y: 0.10, width: 0.70, height: 0.80),
            CGRect(x: 0.20, y: 0.63, width: 0.60, height: 0.27),
            CGRect(x: 0.20, y: 0.10, width: 0.60, height: 0.27),
        ]
        let samples = PanelColourSampler.samples(for: boxes, in: image)
        let regions = zip(boxes, samples).map { box, sample in
            PanelRegion(
                boundingBox: box,
                colourHint: sample.hint,
                colourEvidence: sample.evidence
            )
        }
        let observation = TextObservation(
            text: "NO STOPPING",
            confidence: 0.95,
            boundingBox: CGRect(x: 0.30, y: 0.72, width: 0.40, height: 0.05)
        )

        #expect(!samples[0].evidence.supportsStandalonePanel)
        #expect(samples[1].evidence.supportsStandalonePanel)
        #expect(samples[2].evidence.supportsStandalonePanel)
        #expect(samples[1].evidence.componentID != samples[2].evidence.componentID)
        #expect(
            PanelSegmenter().segment([observation], regions: regions).map(\.rawText)
                == ["NO STOPPING", ""]
        )
    }

    @Test("a pixel bridge does not merge separate panel boundaries")
    func sampledConnectedPanels() throws {
        let image = try #require(Self.connectedPanelImage())
        let boxes = [
            CGRect(x: 0.20, y: 0.63, width: 0.60, height: 0.27),
            CGRect(x: 0.20, y: 0.10, width: 0.60, height: 0.27),
        ]
        let samples = PanelColourSampler.samples(for: boxes, in: image)
        let regions = zip(boxes, samples).map { box, sample in
            PanelRegion(
                boundingBox: box,
                colourHint: sample.hint,
                colourEvidence: sample.evidence
            )
        }

        #expect(samples.map(\.evidence.supportsStandalonePanel) == [true, true])
        #expect(Set(samples.compactMap(\.evidence.componentID)).count == 1)
        #expect(PanelSegmenter().segment([], regions: regions).count == 2)
    }

    @Test("a strong wrapper does not hide a contained panel")
    func sampledStrongWrapper() throws {
        let image = try #require(Self.connectedPanelImage())
        let boxes = [
            CGRect(x: 0.20, y: 0.10, width: 0.60, height: 0.80),
            CGRect(x: 0.20, y: 0.10, width: 0.60, height: 0.27),
        ]
        let samples = PanelColourSampler.samples(for: boxes, in: image)
        let regions = zip(boxes, samples).map { box, sample in
            PanelRegion(
                boundingBox: box,
                colourHint: sample.hint,
                colourEvidence: sample.evidence
            )
        }
        let observation = TextObservation(
            text: "NO STOPPING",
            confidence: 0.95,
            boundingBox: CGRect(x: 0.30, y: 0.74, width: 0.40, height: 0.05)
        )

        #expect(samples.map(\.evidence.supportsStandalonePanel) == [true, true])
        #expect(Set(samples.compactMap(\.evidence.componentID)).count == 1)
        #expect(
            PanelSegmenter().segment([observation], regions: regions).map(\.rawText)
                == ["NO STOPPING", ""]
        )
    }

    @Test("image preparation resizes and applies orientation")
    func imagePreparation() throws {
        let image = try #require(Self.solidImage(width: 400, height: 200))
        let prepared = try #require(
            ImagePreprocessor.prepare(image, orientation: .right, maximumDimension: 100)
        )

        #expect(prepared.width == 50)
        #expect(prepared.height == 100)
    }

    @Test("the on-device Vision request reads a rendered restriction")
    func textRecognition() async throws {
        let image = try #require(Self.renderedSign(withContents: true))

        let reading = try await SignRecognizer().read(image)

        #expect(reading.blocks.count == 1)
        #expect(reading.sign.parsedPanels.map(\.restriction) == [.noStopping])
        #expect(reading.sign.unknowns.isEmpty)
    }

    @Test("a detected panel with no OCR remains an explicit unknown")
    func noTextRecognition() async throws {
        let image = try #require(Self.renderedSign(withContents: false))

        let reading = try await SignRecognizer().read(image)

        #expect(reading.blocks.count == 1)
        #expect(reading.sign.parsedPanels.isEmpty)
        #expect(reading.sign.unknowns.map(\.reason) == [.emptyPanel])
    }

    @Test("low-confidence and empty observations are omitted")
    func noise() {
        let observations = [
            line("NO STOPPING", y: 0.8),
            TextObservation(
                text: "WOMBAT",
                confidence: 0.1,
                boundingBox: CGRect(x: 0.2, y: 0.7, width: 0.4, height: 0.03)
            ),
            TextObservation(
                text: "   ",
                confidence: 0.9,
                boundingBox: CGRect(x: 0.2, y: 0.6, width: 0.4, height: 0.03)
            ),
        ]

        #expect(PanelSegmenter().segment(observations).map(\.rawText) == ["NO STOPPING"])
    }

    @Test("assembled blocks are parsed independently and never dropped")
    func assembly() {
        let blocks = [
            block("NO STOPPING", y: 0.8),
            block("LOADING ZONE", y: 0.5),
        ]

        let sign = SignVision.assemble(blocks)

        #expect(SignVision.pipelineVersion == 3)
        #expect(sign.parsedPanels.count == 1)
        #expect(sign.unknowns.count == 1)
        #expect(sign.unknowns.first?.rawText == "LOADING ZONE")
    }

    @Test("a coloured panel with no readable text becomes an explicit unknown")
    func unreadablePanel() {
        let regions = [
            PanelRegion(
                boundingBox: CGRect(x: 0.1, y: 0.4, width: 0.8, height: 0.3),
                colourHint: .red
            ),
            PanelRegion(
                boundingBox: CGRect(x: 0.3, y: 0.48, width: 0.4, height: 0.1),
                colourHint: .red
            ),
        ]

        let blocks = PanelSegmenter().segment([], regions: regions)
        let sign = SignVision.assemble(blocks)

        #expect(blocks.count == 1)
        #expect(blocks.first?.boundingBox == regions[0].boundingBox)
        #expect(sign.unknowns.count == 1)
        #expect(sign.unknowns.first?.reason == .emptyPanel)
    }

    @Test("wrapped restriction and nested decoration stay one physical panel")
    func fieldPhotoRegression() {
        let observations = [
            TextObservation(
                text: "NO",
                confidence: 0.95,
                boundingBox: CGRect(x: 0.46, y: 0.70, width: 0.08, height: 0.05)
            ),
            TextObservation(
                text: "STOPPING",
                confidence: 0.95,
                boundingBox: CGRect(x: 0.40, y: 0.62, width: 0.20, height: 0.05)
            ),
        ]
        let regions = [
            PanelRegion(
                boundingBox: CGRect(x: 0.35, y: 0.25, width: 0.30, height: 0.55),
                colourHint: .red
            ),
            PanelRegion(
                boundingBox: CGRect(x: 0.42, y: 0.30, width: 0.16, height: 0.06),
                colourHint: .red
            ),
        ]

        let blocks = PanelSegmenter().segment(observations, regions: regions)
        let sign = SignVision.assemble(blocks)

        #expect(blocks.count == 1)
        #expect(blocks.first?.rawText == "NO\nSTOPPING")
        #expect(sign.parsedPanels.map(\.restriction) == [.noStopping])
        #expect(sign.unknowns.isEmpty)
    }

    @Test("shifted decorations do not become extra panels")
    func shiftedFieldPhotoRegression() {
        let observations = [
            TextObservation(
                text: "NO",
                confidence: 0.95,
                boundingBox: CGRect(x: 0.46, y: 0.70, width: 0.08, height: 0.05)
            ),
            TextObservation(
                text: "STOPPING",
                confidence: 0.95,
                boundingBox: CGRect(x: 0.40, y: 0.62, width: 0.20, height: 0.05)
            ),
        ]
        let regions = [
            PanelRegion(
                boundingBox: CGRect(x: 0.35, y: 0.25, width: 0.30, height: 0.55),
                colourHint: .red
            ),
            PanelRegion(
                boundingBox: CGRect(x: 0.32, y: 0.28, width: 0.18, height: 0.12),
                colourHint: .red
            ),
            PanelRegion(
                boundingBox: CGRect(x: 0.50, y: 0.29, width: 0.18, height: 0.12),
                colourHint: .red
            ),
        ]

        let blocks = PanelSegmenter().segment(observations, regions: regions)
        let sign = SignVision.assemble(blocks)

        #expect(blocks.map(\.rawText) == ["NO\nSTOPPING"])
        #expect(sign.parsedPanels.map(\.restriction) == [.noStopping])
        #expect(sign.unknowns.isEmpty)
    }

    @Test("shifted observations of one unreadable panel collapse")
    func shiftedUnreadableDuplicates() {
        let regions = [
            PanelRegion(
                boundingBox: CGRect(x: 0.20, y: 0.40, width: 0.40, height: 0.30),
                colourHint: .red,
                colourEvidence: strongEvidence(componentID: 1)
            ),
            PanelRegion(
                boundingBox: CGRect(x: 0.23, y: 0.38, width: 0.40, height: 0.30),
                colourHint: .red,
                colourEvidence: strongEvidence(componentID: 2)
            ),
        ]

        #expect(PanelSegmenter().segment([], regions: regions).count == 1)
    }

    @Test("duplicate detections preserve separate unreadable panels")
    func separateUnreadablePanels() {
        let regions = [
            PanelRegion(
                boundingBox: CGRect(x: 0.15, y: 0.65, width: 0.70, height: 0.16),
                colourHint: .red
            ),
            PanelRegion(
                boundingBox: CGRect(x: 0.17, y: 0.64, width: 0.70, height: 0.16),
                colourHint: .red
            ),
            PanelRegion(
                boundingBox: CGRect(x: 0.15, y: 0.30, width: 0.70, height: 0.16),
                colourHint: .green
            ),
            PanelRegion(
                boundingBox: CGRect(x: 0.17, y: 0.29, width: 0.70, height: 0.16),
                colourHint: .green
            ),
        ]

        let blocks = PanelSegmenter().segment([], regions: regions)

        #expect(blocks.count == 2)
        #expect(blocks.map(\.colourHint) == [.red, .green])
    }

    @Test("adjacent panels with weak overlap stay separate")
    func adjacentUnreadablePanels() {
        let regions = [
            PanelRegion(
                boundingBox: CGRect(x: 0.10, y: 0.40, width: 0.35, height: 0.25),
                colourHint: .red
            ),
            PanelRegion(
                boundingBox: CGRect(x: 0.38, y: 0.40, width: 0.35, height: 0.25),
                colourHint: .red
            ),
        ]

        #expect(PanelSegmenter().segment([], regions: regions).count == 2)
    }

    @Test("an unclaimed wrapper does not hide a separate unreadable panel")
    func wrapperDoesNotBridgePanels() {
        let observations = [line("NO STOPPING", y: 0.74)]
        let regions = [
            PanelRegion(
                boundingBox: CGRect(x: 0.05, y: 0.20, width: 0.90, height: 0.65)
            ),
            PanelRegion(
                boundingBox: CGRect(x: 0.10, y: 0.68, width: 0.80, height: 0.12),
                colourHint: .red
            ),
            PanelRegion(
                boundingBox: CGRect(x: 0.10, y: 0.32, width: 0.80, height: 0.20),
                colourHint: .green
            ),
        ]

        let blocks = PanelSegmenter().segment(observations, regions: regions)

        #expect(blocks.map(\.rawText) == ["NO STOPPING", ""])
        #expect(blocks.map(\.colourHint) == [.red, .green])
    }

    @Test("a coloured wrapper does not hide a separate unreadable panel")
    func colouredWrapperDoesNotBridgePanels() {
        let observations = [line("NO STOPPING", y: 0.74)]
        let regions = [
            PanelRegion(
                boundingBox: CGRect(x: 0.05, y: 0.20, width: 0.90, height: 0.65),
                colourHint: .red,
                colourEvidence: weakEvidence(componentID: 1)
            ),
            PanelRegion(
                boundingBox: CGRect(x: 0.10, y: 0.68, width: 0.80, height: 0.12),
                colourHint: .red,
                colourEvidence: strongEvidence(componentID: 1)
            ),
            PanelRegion(
                boundingBox: CGRect(x: 0.10, y: 0.32, width: 0.80, height: 0.20),
                colourHint: .red,
                colourEvidence: strongEvidence(componentID: 2)
            ),
        ]

        let blocks = PanelSegmenter().segment(observations, regions: regions)

        #expect(blocks.map(\.rawText) == ["NO STOPPING", ""])
    }

    @Test("weak colour does not establish a panel identity")
    func weakColourDoesNotClaimPanel() {
        let observation = line("NO STOPPING", y: 0.74)
        let weakRegion = PanelRegion(
            boundingBox: CGRect(x: 0.05, y: 0.20, width: 0.90, height: 0.65),
            colourHint: .red,
            colourEvidence: weakEvidence(componentID: 1)
        )
        let tightRegion = PanelRegion(
            boundingBox: CGRect(x: 0.15, y: 0.70, width: 0.70, height: 0.10)
        )

        let block = PanelSegmenter().segment(
            [observation],
            regions: [weakRegion, tightRegion]
        ).first

        #expect(block?.boundingBox == tightRegion.boundingBox)
        #expect(block?.colourHint == PanelColourHint.none)
    }

    @Test("a component representative must contain its OCR line")
    func componentRepresentativeContainsLine() {
        let observation = line("NO STOPPING", y: 0.74)
        let top = PanelRegion(
            boundingBox: CGRect(x: 0.10, y: 0.68, width: 0.80, height: 0.12),
            colourHint: .red,
            colourEvidence: strongEvidence(componentID: 4)
        )
        let bottom = PanelRegion(
            boundingBox: CGRect(x: 0.10, y: 0.32, width: 0.80, height: 0.20),
            colourHint: .red,
            colourEvidence: strongEvidence(componentID: 4)
        )

        let blocks = PanelSegmenter().segment(
            [observation],
            regions: [top, bottom]
        )

        #expect(blocks.map(\.rawText) == ["NO STOPPING", ""])
        #expect(blocks.first?.boundingBox == top.boundingBox)
    }

    @Test("a weak claimed wrapper cannot hide an unreadable panel")
    func weakClaimDoesNotHidePanel() {
        let observation = line("NO STOPPING", y: 0.74)
        let regions = [
            PanelRegion(
                boundingBox: CGRect(x: 0.05, y: 0.20, width: 0.90, height: 0.65),
                colourHint: .red,
                colourEvidence: weakEvidence(componentID: 1)
            ),
            PanelRegion(
                boundingBox: CGRect(x: 0.10, y: 0.32, width: 0.80, height: 0.20),
                colourHint: .red,
                colourEvidence: strongEvidence(componentID: 1)
            ),
        ]

        #expect(
            PanelSegmenter().segment([observation], regions: regions).map(\.rawText)
                == ["NO STOPPING", ""]
        )
    }

    @Test("one unreadable face absorbs disjoint internal shapes")
    func unreadableFaceWithInternalShapes() {
        let regions = [
            PanelRegion(
                boundingBox: CGRect(x: 0.30, y: 0.20, width: 0.40, height: 0.60),
                colourHint: .red,
                colourEvidence: strongEvidence(componentID: 7)
            ),
            PanelRegion(
                boundingBox: CGRect(x: 0.33, y: 0.62, width: 0.12, height: 0.08),
                colourHint: .red,
                colourEvidence: weakEvidence(componentID: 7)
            ),
            PanelRegion(
                boundingBox: CGRect(x: 0.55, y: 0.30, width: 0.12, height: 0.08),
                colourHint: .red,
                colourEvidence: weakEvidence(componentID: 7)
            ),
        ]

        #expect(PanelSegmenter().segment([], regions: regions).count == 1)
    }

    @Test("a rectangle crossing OCR is not an empty panel")
    func partialTextIntersection() {
        let observations = [line("NO STOPPING", y: 0.70)]
        let regions = [
            PanelRegion(
                boundingBox: CGRect(x: 0.40, y: 0.68, width: 0.50, height: 0.10),
                colourHint: .red,
                colourEvidence: strongEvidence(componentID: 1)
            ),
            PanelRegion(
                boundingBox: CGRect(x: 0.18, y: 0.695, width: 0.18, height: 0.04),
                colourHint: .red,
                colourEvidence: strongEvidence(componentID: 2)
            ),
        ]

        #expect(PanelSegmenter().segment(observations, regions: regions).count == 1)
    }

    @Test("discarded OCR still leaves its credible panel unreadable")
    func lowConfidenceUnreadablePanel() {
        let observation = TextObservation(
            text: "WOMBAT",
            confidence: 0.1,
            boundingBox: CGRect(x: 0.25, y: 0.48, width: 0.50, height: 0.05)
        )
        let region = PanelRegion(
            boundingBox: CGRect(x: 0.10, y: 0.40, width: 0.80, height: 0.20),
            colourHint: .red
        )

        let blocks = PanelSegmenter().segment([observation], regions: [region])

        #expect(blocks.count == 1)
        #expect(blocks.first?.rawText == "")
    }

    private func line(_ text: String, y: CGFloat) -> TextObservation {
        TextObservation(
            text: text,
            confidence: 0.95,
            boundingBox: CGRect(x: 0.2, y: y, width: 0.6, height: 0.03)
        )
    }

    private func strongEvidence(componentID: Int) -> PanelColourEvidence {
        PanelColourEvidence(
            insideCoverage: 0.7,
            outsideCoverage: 0,
            perimeterCoverage: 0.7,
            componentShare: 1,
            componentID: componentID,
            standaloneScore: 1
        )
    }

    private func weakEvidence(componentID: Int) -> PanelColourEvidence {
        PanelColourEvidence(
            insideCoverage: 0.1,
            outsideCoverage: 0.1,
            perimeterCoverage: 0,
            componentShare: 0.5,
            componentID: componentID,
            standaloneScore: 0
        )
    }

    private func block(_ text: String, y: CGFloat) -> PanelBlock {
        let observation = line(text, y: y)
        return PanelBlock(
            rawText: text,
            lines: [observation],
            boundingBox: observation.boundingBox
        )
    }

    private static func solidImage(
        width: Int,
        height: Int,
        colour: CGColor = CGColor(gray: 1, alpha: 1)
    ) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(colour)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private static func localizedRedImage() -> CGImage? {
        guard let context = drawingContext(width: 100, height: 100) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        context.setFillColor(CGColor(red: 0.9, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 40, y: 40, width: 20, height: 20))
        return context.makeImage()
    }

    private static func borderImage(
        colour: PanelColourHint,
        dark: Bool = false
    ) -> CGImage? {
        guard let context = drawingContext(width: 240, height: 240) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 240, height: 240))
        context.setFillColor(
            colour == .red
                ? CGColor(
                    red: dark ? 0.38 : 0.9,
                    green: dark ? 0.08 : 0,
                    blue: dark ? 0.08 : 0,
                    alpha: 1
                )
                : CGColor(
                    red: dark ? 0.08 : 0,
                    green: dark ? 0.32 : 0.7,
                    blue: dark ? 0.08 : 0,
                    alpha: 1
                )
        )
        context.fill(CGRect(x: 20, y: 20, width: 200, height: 1))
        context.fill(CGRect(x: 20, y: 219, width: 200, height: 1))
        context.fill(CGRect(x: 20, y: 20, width: 1, height: 200))
        context.fill(CGRect(x: 219, y: 20, width: 1, height: 200))
        return context.makeImage()
    }

    private static func drawingContext(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    private static func colouredPanelImage(stacked: Bool) -> CGImage? {
        guard let context = drawingContext(width: 200, height: 300) else { return nil }
        context.setFillColor(CGColor(gray: 0.85, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 300))
        context.setFillColor(CGColor(red: 0.82, green: 0, blue: 0, alpha: 1))
        if stacked {
            context.fill(CGRect(x: 40, y: 189, width: 120, height: 81))
            context.fill(CGRect(x: 40, y: 30, width: 120, height: 81))
        } else {
            context.fill(CGRect(x: 40, y: 30, width: 120, height: 240))
        }
        return context.makeImage()
    }

    private static func connectedPanelImage() -> CGImage? {
        guard let context = drawingContext(width: 200, height: 300) else { return nil }
        context.setFillColor(CGColor(gray: 0.85, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 300))
        context.setFillColor(CGColor(red: 0.82, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 40, y: 189, width: 120, height: 81))
        context.fill(CGRect(x: 40, y: 30, width: 120, height: 81))
        context.fill(CGRect(x: 99, y: 111, width: 1, height: 78))
        return context.makeImage()
    }

    private static func twoColourImage() -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: 100,
            height: 100,
            bitsPerComponent: 8,
            bytesPerRow: 400,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(red: 0, green: 0.7, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 50))
        context.setFillColor(CGColor(red: 0.9, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 50, width: 100, height: 50))
        return context.makeImage()
    }

    private static func renderedSign(withContents: Bool) -> CGImage? {
        let width = 1_000
        let height = 1_300
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.setFillColor(CGColor(gray: 0.85, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let panel = CGRect(x: 250, y: 100, width: 500, height: 1_100)
        context.setFillColor(CGColor(red: 0.82, green: 0, blue: 0, alpha: 1))
        context.fill(panel)
        context.setStrokeColor(CGColor(gray: 1, alpha: 1))
        context.setLineWidth(12)
        context.stroke(panel.insetBy(dx: 18, dy: 18))

        guard withContents else { return context.makeImage() }

        draw("NO", size: 150, baseline: 920, in: context, canvasWidth: CGFloat(width))
        draw("STOPPING", size: 90, baseline: 750, in: context, canvasWidth: CGFloat(width))

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 385, y: 280, width: 250, height: 34))
        context.beginPath()
        context.move(to: CGPoint(x: 320, y: 297))
        context.addLine(to: CGPoint(x: 410, y: 235))
        context.addLine(to: CGPoint(x: 410, y: 359))
        context.closePath()
        context.fillPath()
        return context.makeImage()
    }

    private static func draw(
        _ string: String,
        size: CGFloat,
        baseline: CGFloat,
        in context: CGContext,
        canvasWidth: CGFloat
    ) {
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
        let text = NSAttributedString(
            string: string,
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                    CGColor(gray: 1, alpha: 1),
            ]
        )
        let line = CTLineCreateWithAttributedString(text)
        let lineWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: (canvasWidth - lineWidth) / 2, y: baseline)
        CTLineDraw(line, context)
    }
}
