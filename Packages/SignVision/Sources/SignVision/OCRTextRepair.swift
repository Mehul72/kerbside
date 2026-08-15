import Foundation

/// Repairs only OCR layouts whose missing information is encoded elsewhere
/// on the same physical plate. The captured text remains untouched; this is
/// used solely as an alternate parser input.
enum OCRTextRepair {
    static func apply(to blocks: [PanelBlock]) -> [PanelBlock] {
        blocks.map { block in
            var repaired = block
            let input = (block.parserTextOverride ?? block.rawText)
                .split(separator: "\n")
                .map { canonical(String($0)) }
                .filter { !$0.isEmpty }
            let output = logicalLines(input)
            let text = output.joined(separator: "\n")
            if !text.isEmpty, text != block.rawText {
                repaired.parserTextOverride = text
            }
            return repaired
        }
    }

    private static func logicalLines(_ input: [String]) -> [String] {
        var lines = input
        var result: [String] = []

        if let no = lines.firstIndex(where: { $0 == "NO" }),
           let restriction = lines.firstIndex(where: {
               $0 == "STOPPING" || $0 == "PARKING"
           }) {
            result.append("NO \(lines[restriction])")
            for index in [no, restriction].sorted(by: >) {
                lines.remove(at: index)
            }
        }

        let bareRanges = lines.indices.filter { isBareTimeRange(lines[$0]) }
        let partialRanges = lines.indices.filter { hasStartAMOnly(lines[$0]) }
        let standalonePM = lines.firstIndex(of: "PM")
        if let standalonePM {
            if partialRanges.count == 1 {
                lines[partialRanges[0]] += "PM"
                lines.remove(at: standalonePM)
            } else if bareRanges.count == 1 {
                lines[bareRanges[0]] = meridiemRange(lines[bareRanges[0]], start: "AM", end: "PM")
                lines.remove(at: standalonePM)
            } else if bareRanges.count == 2 {
                lines[bareRanges[0]] = meridiemRange(lines[bareRanges[0]], start: "AM", end: "AM")
                lines[bareRanges[1]] = meridiemRange(lines[bareRanges[1]], start: "PM", end: "PM")
                lines.remove(at: standalonePM)
            }
        }

        result.append(contentsOf: lines)
        return result
    }

    private static func canonical(_ raw: String) -> String {
        var text = raw.uppercased()
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        // A narrow final G is repeatedly read as I on distant NSW signs.
        if text == "STOPPINI" { text = "STOPPING" }
        return text
    }

    private static func isBareTimeRange(_ text: String) -> Bool {
        text.range(
            of: #"^\d{1,4}\s*-\s*\d{1,4}$"#,
            options: .regularExpression
        ) != nil
    }

    private static func hasStartAMOnly(_ text: String) -> Bool {
        text.range(
            of: #"^\d{1,4}AM\s*-\s*\d{1,4}$"#,
            options: .regularExpression
        ) != nil
    }

    private static func meridiemRange(
        _ text: String,
        start: String,
        end: String
    ) -> String {
        let ends = text.split(separator: "-", maxSplits: 1).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard ends.count == 2 else { return text }
        return "\(ends[0])\(start)-\(ends[1])\(end)"
    }
}
