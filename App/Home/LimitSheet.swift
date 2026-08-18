import ParkKit
import SignKit
import SwiftUI

/// Choosing what the countdown counts.
///
/// The sign's own allowance comes first, stated in full, because it is the only
/// option with provenance. Plain durations follow as a grid of chips: they are
/// interchangeable and identically explained, so giving each one a full-width
/// card with the same sentence under it spent most of the screen saying
/// "counts down from now" seven times over.
struct LimitSheet: View {
    @ObservedObject var controller: ParkingController
    @Environment(\.dismiss) private var dismiss

    private let timeZone = SharedContainer.timeZone
    private static let durations = [15, 30, 60, 120, 180, 240, 480]

    private let columns = [GridItem(.adaptive(minimum: 84), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if !controller.candidates.isEmpty {
                        section("From this sign") {
                            ForEach(Array(controller.candidates.enumerated()), id: \.offset) { _, candidate in
                                SignChoice(
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
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(Self.durations, id: \.self) { minutes in
                                Chip(
                                    label: Self.short(minutes),
                                    selected: isSelected(minutes: minutes)
                                ) {
                                    controller.setLimit(minutes: minutes)
                                    dismiss()
                                }
                                .accessibilityIdentifier("duration-\(minutes)")
                                .accessibilityLabel(Wording.duration(minutes))
                            }
                        }
                        Text("Counts down from now.")
                            .kerbCaption(Kerb.chalkFaint, style: .caption)
                            .padding(.top, 2)
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

    /// `1/4P`-style badges belong on a plate. A chip a person taps to set their
    /// own limit says the duration plainly.
    static func short(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) hr" : "\(hours) hr \(rest)"
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

    /// One plain duration. Small, because there is nothing to say about it.
    private struct Chip: View {
        let label: String
        let selected: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Text(label)
                    .kerbCaption(
                        selected ? Kerb.amber : Kerb.chalk,
                        style: .subheadline,
                        weight: .medium
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .kerbCard(selected ? .primary : .secondary, radius: 11,
                              tint: selected ? Kerb.amber : nil)
            }
            .kerbPressable()
        }
    }

    /// The sign's own allowance. Full width, because unlike a plain duration it
    /// has something to explain.
    private struct SignChoice: View {
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
                            .kerbCaption(
                                enabled ? Kerb.chalk : Kerb.chalkDim,
                                style: .subheadline,
                                weight: .semibold
                            )
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
                .kerbCard(selected ? .primary : .secondary, tint: selected ? Kerb.amber : nil)
            }
            .kerbPressable()
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.65)
        }
    }
}
