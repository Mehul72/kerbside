import ParkKit
import SignKit
import SwiftUI

/// Choosing what the countdown counts.
///
/// The sign's own allowances come first, each stating which panel it was read
/// from and what it means. Below them are plain durations, for a sign that
/// said nothing about time, a sign that was not read, or a ticket that
/// overrules it. Nothing is applied until it is tapped.
struct LimitSheet: View {
    @ObservedObject var controller: ParkingController
    @Environment(\.dismiss) private var dismiss

    private let timeZone = SharedContainer.timeZone
    private static let durations = [15, 30, 60, 120, 180, 240, 480]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    if !controller.candidates.isEmpty {
                        section("From this sign") {
                            ForEach(Array(controller.candidates.enumerated()), id: \.offset) { _, candidate in
                                Choice(
                                    title: Wording.describe(candidate.panel.restriction),
                                    detail: ParkWording.describe(candidate, in: timeZone),
                                    selected: isSelected(candidate),
                                    enabled: candidate.expiry != nil
                                ) {
                                    controller.choose(candidate)
                                    dismiss()
                                }
                            }
                        }
                    }

                    section("Set it yourself") {
                        ForEach(Self.durations, id: \.self) { minutes in
                            Choice(
                                title: Wording.duration(minutes),
                                detail: "Counts down from now.",
                                selected: isSelected(minutes: minutes),
                                enabled: true
                            ) {
                                controller.setLimit(minutes: minutes)
                                dismiss()
                            }
                        }
                    }

                    if controller.spot?.limit.expiry != nil {
                        Button("Remove the limit") {
                            controller.clearLimit()
                            dismiss()
                        }
                        .buttonStyle(PlateButton(kind: .outlined))
                    }

                    Text(
                        "Kerbside does not decide what applies to your car. It counts "
                            + "down whichever limit you pick and says where that limit "
                            + "came from."
                    )
                    .font(Kerb.voice(.footnote))
                    .foregroundStyle(Kerb.chalkFaint)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(24)
            }
            .background(Kerb.asphalt)
            .navigationTitle("Limit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func isSelected(_ candidate: LimitCandidate) -> Bool {
        controller.spot?.limit == candidate.limit
    }

    private func isSelected(minutes: Int) -> Bool {
        if case .chosen(let set) = controller.spot?.limit.source { return set == minutes }
        return false
    }

    @ViewBuilder
    private func section(
        _ title: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).kerbLabel(Kerb.chalkDim, style: .caption)
            content()
        }
    }

    /// One offer. A candidate whose restriction lifts before its allowance is
    /// used up has nothing to count down, so it is shown and explained but
    /// cannot be picked.
    private struct Choice: View {
        let title: String
        let detail: String
        let selected: Bool
        let enabled: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(Kerb.voice(.headline))
                            .foregroundStyle(enabled ? Kerb.chalk : Kerb.chalkDim)
                        Text(detail)
                            .font(Kerb.voice(.footnote))
                            .foregroundStyle(Kerb.chalkDim)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    if selected {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Kerb.amber)
                    }
                }
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(selected ? 0.08 : 0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            selected ? Kerb.amber.opacity(0.7) : Kerb.chalkFaint.opacity(0.3),
                            lineWidth: 1
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.65)
        }
    }
}
