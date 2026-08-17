import ParkKit
import SignKit
import SwiftUI

/// Where the car has been.
///
/// Short by design: the record keeps the last twenty spots, which is enough to
/// answer "where did I leave it on Tuesday" without turning the app into a
/// diary of somebody's movements.
struct PastSpotsView: View {
    @ObservedObject var controller: ParkingController
    @Environment(\.dismiss) private var dismiss
    @State private var isClearing = false

    private let timeZone = SharedContainer.timeZone

    var body: some View {
        NavigationStack {
            List {
                ForEach(controller.record.past) { spot in
                    Row(spot: spot, timeZone: timeZone)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                }
                .onDelete { offsets in
                    for index in offsets {
                        controller.forget(controller.record.past[index].id)
                    }
                }

                if controller.record.past.isEmpty {
                    Text("No spots yet.")
                        .font(Kerb.voice())
                        .foregroundStyle(Kerb.chalkDim)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .padding(.top, 60)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Kerb.asphalt)
            .navigationTitle("Past spots")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if !controller.record.past.isEmpty {
                        Button("Clear") { isClearing = true }
                            .accessibilityIdentifier("clear-history")
                    }
                }
            }
            .confirmationDialog(
                "Forget every past spot?",
                isPresented: $isClearing,
                titleVisibility: .visible
            ) {
                Button("Forget them", role: .destructive) { controller.forgetPast() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Where the car is now is kept. This cannot be undone.")
            }
        }
        .preferredColorScheme(.dark)
    }

    private struct Row: View {
        let spot: ParkingSpot
        let timeZone: TimeZone

        private var headline: String? {
            spot.sign?.parsedPanels.first.map(ParkWording.plateHeadline)
        }

        var body: some View {
            HStack(alignment: .top, spacing: 14) {
                if let headline, let panel = spot.sign?.parsedPanels.first {
                    PlateBadge(text: headline, tone: PlateTone(panel.restriction), size: 13)
                } else {
                    PlateBadge(text: "—", tone: .unread, size: 15)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        ParkWording.dayAndClock(
                            spot.parkedAt,
                            relativeTo: spot.collectedAt ?? spot.parkedAt,
                            in: timeZone
                        )
                    )
                    .font(Kerb.voice(.headline))
                    .foregroundStyle(Kerb.chalk)

                    if !spot.note.isEmpty {
                        Text(spot.note)
                            .font(Kerb.voice(.footnote))
                            .foregroundStyle(Kerb.chalkDim)
                    }

                    if let collected = spot.collectedAt {
                        Text(
                            "Away for "
                                + ParkWording.span(collected.timeIntervalSince(spot.parkedAt))
                        )
                        .kerbLabel(Kerb.chalkFaint, style: .caption2)
                    }

                    if spot.sign == nil {
                        Text("No sign read")
                            .font(Kerb.data(11))
                            .foregroundStyle(Kerb.chalkFaint)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .kerbCard()
        }
    }
}
