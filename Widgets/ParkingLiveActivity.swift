import ActivityKit
import SwiftUI
import WidgetKit

/// The Lock Screen banner and the Dynamic Island.
///
/// Both draw the same three things: which plate the car is under, how long the
/// recorded limit leaves, and where that limit came from. The falling number
/// is drawn by the system from an expiry, so the banner stays right while the
/// app is not running.
struct ParkingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ParkingActivityAttributes.self) { context in
            LockScreenBanner(context: context)
                .activityBackgroundTint(Kerb.asphalt)
                .activitySystemActionForegroundColor(Kerb.amber)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    PlateBadge(
                        text: context.state.headline,
                        tone: context.state.ink.tone,
                        size: 16
                    )
                    .padding(.leading, 4)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    CountdownFigure(
                        expiry: context.state.expiry,
                        now: .now,
                        size: 22
                    )
                    .frame(maxWidth: 92)
                    .padding(.trailing, 4)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.state.attribution)
                            .font(Kerb.voice(.caption))
                            .foregroundStyle(Kerb.chalk)
                            .lineLimit(2)

                        if let distance = context.state.distance {
                            Text(distance)
                                .kerbLabel(Kerb.chalkDim, style: .caption2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: "car.fill")
                    .foregroundStyle(Kerb.amber)
            } compactTrailing: {
                CountdownFigure(expiry: context.state.expiry, now: .now, size: 13)
                    .frame(maxWidth: 56)
            } minimal: {
                CountdownFigure(expiry: context.state.expiry, now: .now, size: 11)
                    .frame(maxWidth: 44)
            }
            .widgetURL(URL(string: "kerbside://spot"))
            .keylineTint(Kerb.amber)
        }
    }
}

private struct LockScreenBanner: View {
    let context: ActivityViewContext<ParkingActivityAttributes>

    private var reading: CountdownReading {
        CountdownReading(
            limit: context.state.expiry.map { .expires(at: $0, source: .chosen(minutes: 0)) }
                ?? .openEnded,
            parkedAt: context.attributes.parkedAt,
            now: .now
        )
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                CountdownRing(progress: reading.progress, urgent: reading.urgent, lineWidth: 6)
                CountdownFigure(expiry: context.state.expiry, now: .now, size: 17)
            }
            .frame(width: 68, height: 68)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    PlateBadge(
                        text: context.state.headline,
                        tone: context.state.ink.tone,
                        size: 14
                    )
                    Spacer(minLength: 0)
                    if let distance = context.state.distance {
                        Text(distance)
                            .kerbLabel(Kerb.chalkDim, style: .caption2)
                    }
                }

                Text(context.state.attribution)
                    .font(Kerb.voice(.caption))
                    .foregroundStyle(Kerb.chalk)
                    .lineLimit(2)

                if let rule = context.state.activeRule {
                    Text(rule)
                        .font(Kerb.voice(.caption2))
                        .foregroundStyle(Kerb.chalkDim)
                        .lineLimit(1)
                }
            }
        }
        .padding(16)
    }
}
