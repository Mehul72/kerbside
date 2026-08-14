import CoreGraphics
import Foundation
import SignKit

/// One line found in a photograph. Bounding boxes use Vision's normalized
/// coordinate space: zero at the bottom-left, one at the top-right.
public struct TextObservation: Hashable, Sendable {
    public var text: String
    public var confidence: Float
    public var boundingBox: CGRect

    public init(text: String, confidence: Float, boundingBox: CGRect) {
        self.text = text
        self.confidence = confidence
        self.boundingBox = boundingBox
    }
}

/// Colour is only a segmentation hint. SignKit never uses it to infer a rule.
public enum PanelColourHint: String, Hashable, Sendable, Codable {
    case red
    case green
    case mixed
    case none
}

/// A rectangular sign-like region found in the photograph.
public struct PanelRegion: Hashable, Sendable {
    public var boundingBox: CGRect
    public var colourHint: PanelColourHint
    public var confidence: Float

    public init(
        boundingBox: CGRect,
        colourHint: PanelColourHint = .none,
        confidence: Float = 1
    ) {
        self.boundingBox = boundingBox
        self.colourHint = colourHint
        self.confidence = confidence
    }
}

/// The raw text and geometry for one physical panel.
public struct PanelBlock: Hashable, Sendable {
    public var rawText: String
    public var lines: [TextObservation]
    public var boundingBox: CGRect
    public var colourHint: PanelColourHint

    public init(
        rawText: String,
        lines: [TextObservation],
        boundingBox: CGRect,
        colourHint: PanelColourHint = .none
    ) {
        self.rawText = rawText
        self.lines = lines
        self.boundingBox = boundingBox
        self.colourHint = colourHint
    }
}

/// A complete on-device reading, including the evidence used to make it.
public struct SignReading: Hashable, Sendable {
    public var sign: Sign
    public var blocks: [PanelBlock]
    public var pipelineVersion: Int

    public init(sign: Sign, blocks: [PanelBlock], pipelineVersion: Int) {
        self.sign = sign
        self.blocks = blocks
        self.pipelineVersion = pipelineVersion
    }
}
