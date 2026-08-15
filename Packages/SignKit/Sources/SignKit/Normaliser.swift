import Foundation

/// One panel's worth of text, before any of it has been understood.
struct Block: Equatable {
    /// The text as it came off the sign, trimmed but otherwise untouched.
    /// This is what an unknown carries and what a panel shows as its source.
    var rawText: String
    /// The same lines, normalised for classification.
    var lines: [String]
}

/// Folds the many ways a sign can spell the same thing into one form.
///
/// Everything here is a pure text transformation. No locale, so `uppercased()`
/// behaves identically wherever this runs.
enum Normaliser {
    static let homoglyphs: [Character: Character] = [
        "\u{0410}": "A", "\u{0412}": "B", "\u{0421}": "C", "\u{0415}": "E",
        "\u{041D}": "H", "\u{041A}": "K", "\u{041C}": "M", "\u{041E}": "O",
        "\u{0420}": "P", "\u{0422}": "T", "\u{0425}": "X", "\u{0423}": "Y",
        "\u{0406}": "I", "\u{0405}": "S",
        "\u{0391}": "A", "\u{0392}": "B", "\u{0395}": "E", "\u{0396}": "Z",
        "\u{0397}": "H", "\u{0399}": "I", "\u{039A}": "K", "\u{039C}": "M",
        "\u{039D}": "N", "\u{039F}": "O", "\u{03A1}": "P", "\u{03A4}": "T",
        "\u{03A5}": "Y", "\u{03A7}": "X",
    ]

    private static let leftArrows = ["<->", "<=>", "<-", "<=", "\u{2190}", "\u{27F5}", "\u{2B05}"]

    static func splitIntoBlocks(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var rawLines: [String] = []

        func flush() {
            let kept = rawLines.filter { !$0.isEmpty }
            rawLines = []
            guard !kept.isEmpty else { return }
            let normalised = kept.map(normalise(line:)).filter { !$0.isEmpty }
            blocks.append(Block(rawText: kept.joined(separator: "\n"), lines: normalised))
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flush()
            } else {
                rawLines.append(trimmed)
            }
        }
        flush()
        return blocks
    }

    static func normalise(line: String) -> String {
        var text = line.uppercased()

        // ASCII arrows first: they contain dashes and equals signs that the
        // later folding would otherwise eat.
        text = text.replacingOccurrences(of: "<->", with: "\u{2194}")
        text = text.replacingOccurrences(of: "<=>", with: "\u{2194}")
        text = text.replacingOccurrences(of: "<-", with: "\u{2190}")
        text = text.replacingOccurrences(of: "<=", with: "\u{2190}")
        text = text.replacingOccurrences(of: "->", with: "\u{2192}")
        text = text.replacingOccurrences(of: "=>", with: "\u{2192}")

        text = text.replacingOccurrences(of: "A.M.", with: "AM")
        text = text.replacingOccurrences(of: "P.M.", with: "PM")

        var folded = ""
        folded.reserveCapacity(text.count)
        for character in text {
            // Text recognition sometimes returns a Cyrillic or Greek letter
            // that is drawn identically to the Latin one, so AM comes back
            // spelled with a Cyrillic M and nothing matches. Folding them is
            // safe: no NSW parking sign is written in either alphabet.
            if let latin = Self.homoglyphs[character] {
                folded.append(latin)
                continue
            }
            switch character {
            case "\u{2013}", "\u{2014}", "\u{2212}", "\u{2010}", "\u{2011}", "\u{2012}":
                folded.append("-")
            case "\u{27F5}", "\u{2B05}":
                folded.append("\u{2190}")
            case "\u{27F6}", "\u{27A1}", "\u{2B95}":
                folded.append("\u{2192}")
            case "\u{27F7}", "\u{2B0C}":
                folded.append("\u{2194}")
            default:
                folded.append(character)
            }
        }

        // " TO " is a separator, the same as a dash.
        folded = folded.replacingOccurrences(of: " TO ", with: " - ")

        let collapsed = folded.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: ".;,"))
    }
}
