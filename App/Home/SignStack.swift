import ParkKit
import SignKit
import SwiftUI

/// The sign over the car, drawn as the pole it is.
///
/// Panels that are in force now are lit; panels outside their hours are
/// dimmed. Panels that were never understood are neither: they stand at full
/// strength in the order they appeared, because an unread panel is a result
/// and not an omission.
struct SignStack: View {
    let sign: Sign
    let evaluation: Evaluation?
    var width: CGFloat = Kerb.plateWidth

    private var activePanels: Set<Panel> {
        Set(evaluation?.active ?? [])
    }

    var body: some View {
        ZStack {
            PoleSpine()
            VStack(spacing: Kerb.plateGap) {
                ForEach(Array(sign.panels.enumerated()), id: \.offset) { index, result in
                    plate(for: result)
                        .entering(index)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func plate(for result: PanelResult) -> some View {
        switch result {
        case .panel(let panel):
            PanelPlate(panel: panel, lit: activePanels.contains(panel))
                .considerate(Kerb.Motion.settle, value: activePanels.contains(panel))
        case .unknown(let unknown):
            UnknownPlate(unknown: unknown)
        }
    }
}

/// What the sign says right now, in words.
///
/// Both halves are stated: the rules in force, and the next thing that
/// changes. Neither is a conclusion about the car — the sentence names the
/// panel and the clock and stops there.
struct RuleNow: View {
    let evaluation: Evaluation
    let timeZone: TimeZone

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if evaluation.active.isEmpty {
                Row(
                    label: "In force now",
                    text: "Nothing on this sign applies at the moment.",
                    ink: Kerb.chalkDim
                )
            } else {
                ForEach(Array(evaluation.active.enumerated()), id: \.offset) { _, panel in
                    Row(
                        label: "In force now",
                        text: Wording.describe(panel),
                        ink: PlateTone(panel.restriction).ink
                    )
                }
            }

            if let change = evaluation.nextChange {
                Row(
                    label: change.kind == .begins ? "Starts next" : "Lifts next",
                    text: "\(Wording.describe(change.panel)), at "
                        + "\(ParkWording.dayAndClock(change.at, relativeTo: evaluation.instant, in: timeZone)).",
                    ink: Kerb.amber
                )
            }

            ForEach(Array(evaluation.unknowns.enumerated()), id: \.offset) { _, unknown in
                Row(
                    label: "Not read",
                    text: Wording.describe(unknown.reason),
                    ink: Kerb.chalkFaint
                )
            }
        }
    }

    private struct Row: View {
        let label: String
        let text: String
        let ink: Color

        var body: some View {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Circle().fill(ink).frame(width: 6, height: 6)
                    Text(label).kerbLabel(Kerb.chalkDim, style: .caption2)
                }
                Text(text)
                    .font(Kerb.voice(.subheadline))
                    .foregroundStyle(Kerb.chalk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
