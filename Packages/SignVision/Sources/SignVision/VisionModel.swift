import CoreGraphics
import Foundation
import SignKit

/// One line found in a photograph. Bounding boxes use Vision's normalized
/// coordinate space: zero at the bottom-left, one at the top-right.
public struct TextObservation: Hashable, Sendable {
    public var text: String
    public var confidence: Float
    public var boundingBox: CGRect
    /// The colour of the plate this line sits on, when it could be sampled.
    ///
    /// Only ever a segmentation hint. It separates one sign from the next when
    /// no rectangle was detected around either; it never contributes to what a
    /// panel is taken to say.
    public var colourHint: PanelColourHint

    public init(
        text: String,
        confidence: Float,
        boundingBox: CGRect,
        colourHint: PanelColourHint = .none
    ) {
        self.text = text
        self.confidence = confidence
        self.boundingBox = boundingBox
        self.colourHint = colourHint
    }
}

/// Colour is only a segmentation hint. SignKit never uses it to infer a rule.
public enum PanelColourHint: String, Hashable, Sendable, Codable {
    case red
    case green
    case mixed
    case none
}

/// A direction read from one graphical arrow rather than OCR text.
///
/// There is deliberately no unknown case: absence or ambiguity is represented
/// by no observation, and two opposing detections are never widened to both.
public enum VisualDirection: String, Hashable, Sendable {
    case left
    case right
    case bidirectional
}

/// Quantitative image evidence retained alongside a rectangle.
///
/// A real coloured face or outline reaches all four edges of its rectangle and
/// is separated from the same connected colour outside it. A word, arrow, tree
/// branch, or rectangle that merely crosses a sign does not provide that same
/// boundary evidence.
public struct PanelColourEvidence: Hashable, Sendable {
    public var insideCoverage: Float
    public var outsideCoverage: Float
    public var perimeterCoverage: Float
    public var componentShare: Float
    public var componentID: Int?
    public var standaloneScore: Float

    public init(
        insideCoverage: Float,
        outsideCoverage: Float,
        perimeterCoverage: Float,
        componentShare: Float,
        componentID: Int?,
        standaloneScore: Float
    ) {
        self.insideCoverage = insideCoverage
        self.outsideCoverage = outsideCoverage
        self.perimeterCoverage = perimeterCoverage
        self.componentShare = componentShare
        self.componentID = componentID
        self.standaloneScore = standaloneScore
    }

    public var supportsStandalonePanel: Bool {
        standaloneScore > 0
    }

    public static let none = PanelColourEvidence(
        insideCoverage: 0,
        outsideCoverage: 0,
        perimeterCoverage: 0,
        componentShare: 0,
        componentID: nil,
        standaloneScore: 0
    )

    static func assumed(for hint: PanelColourHint) -> PanelColourEvidence {
        guard hint != .none else { return .none }
        return PanelColourEvidence(
            insideCoverage: 1,
            outsideCoverage: 0,
            perimeterCoverage: 1,
            componentShare: 1,
            componentID: nil,
            standaloneScore: 1
        )
    }
}

/// A rectangular sign-like region found in the photograph.
public struct PanelRegion: Hashable, Sendable {
    public var boundingBox: CGRect
    public var colourHint: PanelColourHint
    public var colourEvidence: PanelColourEvidence
    public var confidence: Float

    public init(
        boundingBox: CGRect,
        colourHint: PanelColourHint = .none,
        colourEvidence: PanelColourEvidence? = nil,
        confidence: Float = 1
    ) {
        self.boundingBox = boundingBox
        self.colourHint = colourHint
        self.colourEvidence = colourEvidence ?? .assumed(for: colourHint)
        self.confidence = confidence
    }
}

/// The raw text and geometry for one physical panel.
public struct PanelBlock: Hashable, Sendable {
    public var rawText: String
    public var lines: [TextObservation]
    public var boundingBox: CGRect
    public var colourHint: PanelColourHint
    public var sourceRegion: PanelRegion?
    public var visualDirection: VisualDirection?
    var parserTextOverride: String?

    public init(
        rawText: String,
        lines: [TextObservation],
        boundingBox: CGRect,
        colourHint: PanelColourHint = .none,
        sourceRegion: PanelRegion? = nil,
        visualDirection: VisualDirection? = nil
    ) {
        self.rawText = rawText
        self.lines = lines
        self.boundingBox = boundingBox
        self.colourHint = colourHint
        self.sourceRegion = sourceRegion
        self.visualDirection = visualDirection
        parserTextOverride = nil
    }
}

/// A complete on-device reading, including the evidence used to make it.
public struct SignReading: Hashable, Sendable {
    public var sign: Sign
    public var blocks: [PanelBlock]
    /// Every candidate sign face the rectangle pass proposed, kept whether or
    /// not a block used it. Arrow detection is gated on these, so when no
    /// arrow is found this is the evidence that says why.
    public var regions: [PanelRegion]
    public var pipelineVersion: Int

    public init(
        sign: Sign,
        blocks: [PanelBlock],
        regions: [PanelRegion] = [],
        pipelineVersion: Int
    ) {
        self.sign = sign
        self.blocks = blocks
        self.regions = regions
        self.pipelineVersion = pipelineVersion
    }
}
