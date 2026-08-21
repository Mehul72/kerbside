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

        for (lineDirections, token) in classifyLogicalLines(foldMeridiems(block.lines)) {
            directions.append(contentsOf: lineDirections)

            switch token {
            case .none:
                continue
            case .restriction(let restriction, let lineQualifiers):
                restrictions.append(restriction)
                qualifiers.append(contentsOf: lineQualifiers)
            case .timeRanges(let ranges):
                timeRanges.append(contentsOf: ranges)
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
        guard Set(daySets).count <= 1 else { return fail(.conflictingDaySets) }

        return .panel(
            Panel(
                restriction: restriction,
                days: daySets.first ?? .allDays,
                times: TimeWindows(timeRanges),
                direction: resolve(directions),
                qualifiers: canonical(qualifiers),
                rawText: block.rawText
            )
        )
    }

    /// Reattaches AM and PM to the times they belong to.
    ///
    /// NSW signs set the meridiem in small type beneath the numerals, so text
    /// recognition returns it as its own line: `9 30 - 3 30` followed by
    /// `AM PM`. Left alone that line is unreadable and takes the whole panel
    /// down with it, even though the sign is perfectly clear to a person.
    ///
    /// Only a line that is nothing but two markers is folded, and only onto a
    /// window with two ends. A single stray marker cannot be placed without
    /// guessing which end it belongs to, so it is left to fail.
    static func foldMeridiems(_ lines: [String]) -> [String] {
        var result: [String] = []

        for line in lines {
            let markers = line.split(separator: " ").map(String.init)
            guard markers.count == 2,
                  markers.allSatisfy({ $0 == "AM" || $0 == "PM" }),
                  let previous = result.last
            else {
                result.append(line)
                continue
            }

            let ends = previous.split(separator: "-", omittingEmptySubsequences: false)
            guard ends.count == 2 else {
                result.append(line)
                continue
            }
            let start = ends[0].trimmingCharacters(in: .whitespaces)
            let end = ends[1].trimmingCharacters(in: .whitespaces)
            guard !start.isEmpty, !end.isEmpty,
                  !start.hasSuffix("AM"), !start.hasSuffix("PM"),
                  !end.hasSuffix("AM"), !end.hasSuffix("PM")
            else {
                result.append(line)
                continue
            }

            result[result.count - 1] = "\(start)\(markers[0]) - \(end)\(markers[1])"
        }
        return result
    }

    /// Vision can return a visually wrapped phrase as one observation per
    /// word. Join at most three adjacent rejected lines when their combined
    /// text is a complete known token. The classifier remains authoritative:
    /// arbitrary neighbouring lines are never combined or partially accepted.
    private static func classifyLogicalLines(
        _ lines: [String]
    ) -> [(directions: [Direction], token: LineToken?)] {
        var result: [(directions: [Direction], token: LineToken?)] = []
        var index = 0

        while index < lines.count {
            let direct = LineClassifier.classify(lines[index])
            guard case .unrecognised = direct.token else {
                result.append(direct)
                index += 1
                continue
            }

            var combined: (directions: [Direction], token: LineToken?)?
            var consumed = 1
            let maximumCount = min(3, lines.count - index)
            if maximumCount >= 2 {
                for count in stride(from: maximumCount, through: 2, by: -1) {
                    let text = lines[index..<(index + count)].joined(separator: " ")
                    let candidate = LineClassifier.classify(text)
                    if isCompleteToken(candidate.token) {
                        combined = candidate
                        consumed = count
                        break
                    }
                }
            }

            result.append(combined ?? direct)
            index += consumed
        }
        return result
    }

    private static func isCompleteToken(_ token: LineToken?) -> Bool {
        switch token {
        case .restriction, .timeRanges, .daySet, .qualifier, .malformedTimeRange:
            true
        case .none, .unrecognised:
            false
        }
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
