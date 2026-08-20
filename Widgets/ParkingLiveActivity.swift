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
            let window = allowanceWindow(context.state)
            let overrun = hasOverrun(context)

            return DynamicIsland {
                // Everything lives in the bottom region.
                //
                // The regions either side of the camera are far narrower than
                // they look, and anything substantial put in them overflows
                // the island's mask — the plate lost its left edge and its
                // top, the count lost its last digit. The bottom region gets
                // the island's full span, so the whole reading is composed
                // there instead.
                //
                // Every inset here is padding inside the content, never
                // `contentMargins`. That modifier replaces the system's own
                // margins instead of adding to them, so asking for a small one
                // moves content outwards — which is how the sentence lost its
                // first letter the first time round. Padding is additive, so
                // it can only ever pull content further from the curve.
                //
                // Insetting matters more here than the flat corner radius
                // suggests: the pill's ends are round, so the width actually
                // available shrinks towards the top and bottom of the island,
                // exactly where these rows sit.

                // Small enough to sit beside the camera without meeting the
                // mask. Anything with real width belongs below.
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "car.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(overrun ? Kerb.overdue : Kerb.amber)
                        .padding(.leading, 6)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    if let distance = context.state.distance {
                        Text(distance)
                            .font(Kerb.voice(.caption2))
                            .foregroundStyle(Kerb.chalkDim)
                            .lineLimit(1)
                            .padding(.trailing, 6)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .center, spacing: 10) {
                            PlateBadge(
                                text: context.state.headline,
                                tone: context.state.ink.tone,
                                size: 13
                            )

                            Spacer(minLength: 8)

                            CountdownFigure(
                                expiry: context.state.expiry,
                                now: .now,
                                size: 22,
                                alignment: .trailing
                            )
                        }

                        TimeBar(window: window, overrun: overrun)

                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            // One line. The island caps its own height, and
                            // a second line pushed this row off the bottom
                            // edge entirely.
                            Text(context.state.attribution)
                                .font(Kerb.voice(.caption))
                                .foregroundStyle(Kerb.chalk)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)

                            Spacer(minLength: 0)
                        }
                    }
                    .padding(.horizontal, 10)
                }
            } compactLeading: {
                Image(systemName: "car.fill")
                    .foregroundStyle(overrun ? Kerb.overdue : Kerb.amber)
            } compactTrailing: {
                CountdownFigure(expiry: context.state.expiry, now: .now, size: 13)
            } minimal: {
                CountdownFigure(expiry: context.state.expiry, now: .now, size: 11)
            }
            .widgetURL(URL(string: "kerbside://spot"))
            .keylineTint(overrun ? Kerb.overdue : Kerb.amber)
        }
    }
}

/// The span the allowance runs across, when there is one.
///
/// Shared by the banner and the island so the two cannot disagree about how
/// much of the allowance is gone.
private func allowanceWindow(
    _ state: ParkingActivityAttributes.ContentState
) -> ClosedRange<Date>? {
    guard let expiry = state.expiry,
          let started = state.startedAt,
          started < expiry
    else { return nil }
    return started...expiry
}

/// Whether the limit has run out. `isStale` is set by ActivityKit at the stale
/// date the app supplied, which is the expiry, so it is true exactly when the
/// figure has turned around and started counting up.
private func hasOverrun(_ context: ActivityViewContext<ParkingActivityAttributes>) -> Bool {
    guard let expiry = context.state.expiry else { return false }
    return context.isStale || expiry <= .now
}

/// The countdown ring, unrolled.
///
/// The Dynamic Island is a wide, shallow canvas and a circle spends it badly,
/// so the allowance is drawn straight across instead. It is the same reading
/// the ring gives on every other surface, in the shape this one actually has.
///
/// Drawn by the system rather than by this view: a Live Activity is rendered
/// out of process and only redrawn when its state changes, so a bar computed
/// from `Date.now` would freeze at whatever instant it last rendered while the
/// figure above it kept ticking. `ProgressView(timerInterval:)` is the one
/// progress the system animates on its own, so it drains honestly with the app
/// closed.
private struct TimeBar: View {
    let window: ClosedRange<Date>?
    let overrun: Bool

    var body: some View {
        Group {
            if let window, !overrun {
                ProgressView(timerInterval: window, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.linear)
                .tint(Kerb.amber)
                .labelsHidden()
            } else {
                // Nothing to drain: either no limit was set, or it has passed
                // and the figure is counting the other way.
                Capsule()
                    .fill(overrun ? Kerb.overdue : Kerb.chalkFaint.opacity(0.22))
                    .frame(height: 4)
                    .shadow(color: overrun ? Kerb.overdue.opacity(0.5) : .clear, radius: 6)
            }
        }
        .frame(height: 4)
    }
}

private struct LockScreenBanner: View {
    let context: ActivityViewContext<ParkingActivityAttributes>

    private var window: ClosedRange<Date>? { allowanceWindow(context.state) }

    private var overrun: Bool { hasOverrun(context) }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                // Drawn by the system rather than by this view.
                //
                // A Live Activity is rendered out of process and only redrawn
                // when its state changes, so a ring computed from `Date.now`
                // freezes at whatever instant it last rendered while the figure
                // beside it keeps ticking. `ProgressView(timerInterval:)` is
                // the one progress the system animates on its own, so it stays
                // honest without the app running.
                if let window, !overrun {
                    ProgressView(timerInterval: window, countsDown: true) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                    .progressViewStyle(.circular)
                    .tint(Kerb.amber)
                    .labelsHidden()
                } else {
                    Circle()
                        .stroke(
                            overrun ? Kerb.overdue : Kerb.chalkFaint.opacity(0.25),
                            lineWidth: 6
                        )
                        .shadow(color: overrun ? Kerb.overdue.opacity(0.6) : .clear, radius: 10)
                }

                CountdownFigure(expiry: context.state.expiry, now: .now, size: 16)
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

                if overrun {
                    Text("Over that limit now")
                        .kerbLabel(Kerb.amber, style: .caption2)
                } else if let rule = context.state.activeRule {
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
