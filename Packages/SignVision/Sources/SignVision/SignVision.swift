import Foundation
import SignKit

/// Entry points shared by the Vision-backed recognizer and deterministic tests.
public enum SignVision {
    /// Incremented when recognition or segmentation changes materially.
    public static let pipelineVersion = 4

    /// Parses panel blocks independently, preserving their top-to-bottom order.
    /// Understanding text stays in SignKit; SignVision only supplies boundaries.
    public static func assemble(_ blocks: [PanelBlock]) -> Sign {
        Sign(
            panels: blocks.flatMap { block -> [PanelResult] in
                if block.rawText.isEmpty {
                    return [.unknown(Unknown(rawText: "", reason: .emptyPanel))]
                }
                var parsed = Parser.parse(
                    block.parserTextOverride ?? block.rawText
                ).panels
                if parsed.isEmpty, block.parserTextOverride != nil {
                    parsed = Parser.parse(block.rawText).panels
                }
                if block.parserTextOverride != nil {
                    parsed = parsed.map { result in
                        switch result {
                        case .panel(var panel):
                            panel.rawText = block.rawText
                            return .panel(panel)
                        case .unknown(var unknown):
                            unknown.rawText = block.rawText
                            return .unknown(unknown)
                        }
                    }
                }
                guard parsed.count == 1,
                      let visualDirection = block.visualDirection,
                      case .panel(var panel) = parsed[0],
                      panel.direction == .unspecified
                else { return parsed }

                switch visualDirection {
                case .left: panel.direction = .left
                case .right: panel.direction = .right
                case .bidirectional: panel.direction = .both
                }
                return [.panel(panel)]
            }
        )
    }
}
