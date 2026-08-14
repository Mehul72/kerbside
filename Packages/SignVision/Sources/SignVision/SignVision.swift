import Foundation
import SignKit

/// Entry points shared by the Vision-backed recognizer and deterministic tests.
public enum SignVision {
    /// Incremented when recognition or segmentation changes materially.
    public static let pipelineVersion = 1

    /// Parses panel blocks independently, preserving their top-to-bottom order.
    /// Understanding text stays in SignKit; SignVision only supplies boundaries.
    public static func assemble(_ blocks: [PanelBlock]) -> Sign {
        Sign(
            panels: blocks.flatMap { block -> [PanelResult] in
                if block.rawText.isEmpty {
                    return [.unknown(Unknown(rawText: "", reason: .emptyPanel))]
                }
                return Parser.parse(block.rawText).panels
            }
        )
    }
}
