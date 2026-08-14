import Foundation

/// Reads the text of a pole of signs into panels.
///
/// Pure: no clock, no locale, no network, no dictionary iteration order
/// reaching the result. The same string always produces the same `Sign`.
public enum Parser {
    public static func parse(_ text: String) -> Sign {
        Sign(panels: Normaliser.splitIntoBlocks(text).map(assemble(block:)))
    }

    static func assemble(block: Block) -> PanelResult {
        func fail(_ reason: UnknownReason) -> PanelResult {
            .unknown(Unknown(rawText: block.rawText, reason: reason))
        }

        guard !block.lines.isEmpty else { return fail(.emptyPanel) }

        var directions: [Direction] = []
        var restrictions: [Restriction] = []
        var timeRanges: [TimeRange] = []
        var daySets: [DaySet] = []
        var qualifiers: [Qualifier] = []
        // The first line that defeated the classifier, in sign order.
        var lineFailure: UnknownReason?

        for line in block.lines {
            let (lineDirections, token) = LineClassifier.classify(line)
            directions.append(contentsOf: lineDirections)

            switch token {
            case .none:
                continue
            case .restriction(let restriction):
                restrictions.append(restriction)
            case .timeRange(let range):
                timeRanges.append(range)
            case .daySet(let days):
                daySets.append(days)
            case .qualifier(let qualifier):
                qualifiers.append(qualifier)
            case .malformedTimeRange(let raw):
                if lineFailure == nil { lineFailure = .malformedTimeRange(raw) }
            case .unrecognised(let raw):
                if lineFailure == nil { lineFailure = .unrecognisedLine(raw) }
            }
        }

        // A line nobody could read takes its whole panel down. A panel is never
        // reported half read.
        if let lineFailure { return fail(lineFailure) }

        guard let restriction = restrictions.first else { return fail(.noRestrictionFound) }
        guard Set(restrictions).count == 1 else { return fail(.conflictingRestrictions) }
        guard Set(timeRanges).count <= 1 else { return fail(.conflictingTimeRanges) }
        guard Set(daySets).count <= 1 else { return fail(.conflictingDaySets) }

        return .panel(
            Panel(
                restriction: restriction,
                days: daySets.first ?? .allDays,
                times: timeRanges.first ?? .allDay,
                direction: resolve(directions),
                qualifiers: canonical(qualifiers),
                rawText: block.rawText
            )
        )
    }

    /// Arrows pointing both ways describe both stretches of kerb. No arrow at
    /// all stays unspecified rather than being widened to both.
    private static func resolve(_ directions: [Direction]) -> Direction {
        let found = Set(directions)
        if found.isEmpty { return .unspecified }
        if found == [.left] { return .left }
        if found == [.right] { return .right }
        return .both
    }

    /// Deduplicated and in a fixed order, so two spellings of the same panel
    /// cannot produce two different values.
    private static func canonical(_ qualifiers: [Qualifier]) -> [Qualifier] {
        let found = Set(qualifiers)
        return Qualifier.allCases.filter(found.contains)
    }
}
