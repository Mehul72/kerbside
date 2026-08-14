import Foundation
import SignKit

// A development tool for reading sign text at the command line. It exists so a
// panel can be tried without a simulator. It is not part of the app.

let arguments = Array(CommandLine.arguments.dropFirst())
let wantsJSON = arguments.contains("--json")
let textArguments = arguments.filter { $0 != "--json" }

let input: String
if textArguments.isEmpty {
    var stdinText = ""
    while let line = readLine(strippingNewline: false) {
        stdinText += line
    }
    input = stdinText
} else {
    input = textArguments.joined(separator: "\n")
}

let sign = Parser.parse(input)

if wantsJSON {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
    if let data = try? encoder.encode(sign), let text = String(data: data, encoding: .utf8) {
        print(text)
    } else {
        FileHandle.standardError.write(Data("could not encode this sign\n".utf8))
        exit(1)
    }
} else if sign.panels.isEmpty {
    print("No panels. Nothing on the input looked like a sign.")
} else {
    for (index, result) in sign.panels.enumerated() {
        print("Panel \(index + 1)")
        switch result {
        case .panel(let panel):
            print("  \(Wording.describe(panel))")
        case .unknown(let unknown):
            print("  Not read. \(Wording.describe(unknown.reason))")
        }
        let raw = switch result {
        case .panel(let panel): panel.rawText
        case .unknown(let unknown): unknown.rawText
        }
        for line in raw.split(separator: "\n") {
            print("  | \(line)")
        }
        print("")
    }
}
