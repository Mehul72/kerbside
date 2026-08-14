import SignKit
import Testing

@testable import SignVision

struct SignVisionTests {
    /// Stage 3 fills this package in. Until then the only thing worth holding
    /// is that it reaches SignKit, since recognition has to hand its blocks
    /// somewhere and must not grow a parser of its own.
    @Test("the vision package can reach the parser")
    func reachesSignKit() {
        #expect(SignVision.pipelineVersion == 0)
        #expect(Parser.parse("NO STOPPING").parsedPanels.count == 1)
    }
}
