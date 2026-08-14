import Foundation
import SignKit

/// Stage 3 turns a photograph into the block text that `SignKit.Parser` reads.
///
/// Nothing here parses. Recognising text and segmenting panels is this
/// package's whole job; understanding them belongs to SignKit.
public enum SignVision {
    /// The version of the recognition pipeline, so a stored reading can be
    /// told apart from one produced by a later build.
    public static let pipelineVersion = 0
}
