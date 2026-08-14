import SignKit
import SwiftUI

/// Stage 4 replaces the text field with the camera. Until then this is enough
/// of a shell to see a real `Sign` rendered on a device.
///
/// The list has no verdict in it. Every panel, readable or not, gets a row.
struct SignView: View {
    @State private var text = ""

    private var sign: Sign { Parser.parse(text) }

    var body: some View {
        NavigationStack {
            List {
                Section("Sign text") {
                    TextEditor(text: $text)
                        .frame(minHeight: 120)
                        .font(.body.monospaced())
                }

                if sign.panels.isEmpty {
                    Section {
                        Text("No panels read yet.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Panels") {
                        ForEach(Array(sign.panels.enumerated()), id: \.offset) { pair in
                            PanelRow(result: pair.element)
                        }
                    }
                }
            }
            .navigationTitle("Kerbside")
        }
    }
}

/// An unreadable panel is shown as prominently as a readable one. It is a
/// result, not an error, so it gets the same row treatment and keeps its text.
private struct PanelRow: View {
    let result: PanelResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch result {
            case .panel(let panel):
                Text(Wording.describe(panel))
                    .font(.headline)
            case .unknown(let unknown):
                Text("Not read")
                    .font(.headline)
                Text(Wording.describe(unknown.reason))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(rawText)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var rawText: String {
        switch result {
        case .panel(let panel): panel.rawText
        case .unknown(let unknown): unknown.rawText
        }
    }
}
