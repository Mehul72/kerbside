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
        let image = try #require(Self.renderedSign())

        let reading = try await SignRecognizer().read(image)

        #expect(reading.blocks.contains { $0.rawText.contains("NO STOPPING") })
        #expect(reading.sign.parsedPanels.contains { $0.restriction == .noStopping })
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

        #expect(SignVision.pipelineVersion == 1)
        #expect(sign.parsedPanels.count == 1)
        #expect(sign.unknowns.count == 1)
        #expect(sign.unknowns.first?.rawText == "LOADING ZONE")
    }

    @Test("a coloured panel with no readable text becomes an explicit unknown")
    func unreadablePanel() {
        let region = PanelRegion(
            boundingBox: CGRect(x: 0.1, y: 0.4, width: 0.8, height: 0.3),
            colourHint: .red
        )

        let blocks = PanelSegmenter().segment([], regions: [region])
        let sign = SignVision.assemble(blocks)

        #expect(blocks.count == 1)
        #expect(sign.unknowns.count == 1)
        #expect(sign.unknowns.first?.reason == .emptyPanel)
    }

    private func line(_ text: String, y: CGFloat) -> TextObservation {
        TextObservation(
            text: text,
            confidence: 0.95,
            boundingBox: CGRect(x: 0.2, y: y, width: 0.6, height: 0.03)
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

    private static func solidImage(width: Int, height: Int) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
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

    private static func renderedSign() -> CGImage? {
        let width = 1_000
        let height = 500
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setStrokeColor(CGColor(red: 0.85, green: 0, blue: 0, alpha: 1))
        context.setLineWidth(14)
        context.stroke(CGRect(x: 35, y: 35, width: 930, height: 430))

        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 112, nil)
        let text = NSAttributedString(
            string: "NO STOPPING",
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                    CGColor(gray: 0, alpha: 1),
            ]
        )
        let line = CTLineCreateWithAttributedString(text)
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: 110, y: 200)
        CTLineDraw(line, context)
        return context.makeImage()
    }
}
