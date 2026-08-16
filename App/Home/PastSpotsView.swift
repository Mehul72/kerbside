import ParkKit
import SignKit
import SwiftUI

/// Where the car has been.
///
/// Short by design: the record keeps the last twenty spots, which is enough to
/// answer "where did I leave it on Tuesday" without turning the app into a
/// diary of somebody's movements.
struct PastSpotsView: View {
    let record: ParkingRecord
    @Environment(\.dismiss) private var dismiss

    private let timeZone = SharedContainer.timeZone

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(record.past) { spot in
                        Row(spot: spot, timeZone: timeZone)
                    }

                    if record.past.isEmpty {
                        Text("No spots yet.")
                            .font(Kerb.voice())
                            .foregroundStyle(Kerb.chalkDim)
                            .padding(.top, 60)
                    }
                }
                .padding(22)
            }
            .background(Kerb.asphalt)
            .navigationTitle("Past spots")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
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
            .background(Color.white.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Kerb.chalkFaint.opacity(0.3), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}
