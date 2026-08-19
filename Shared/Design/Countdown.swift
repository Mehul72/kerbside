import ParkKit
import SwiftUI

/// The ring around a countdown.
///
/// It depletes as the allowance is used, in amber, because amber is this app's
/// colour for time. Once the limit has passed it fills again in `overdue` red —
/// a hue held apart from a plate's `signRed` on purpose. The plate's red is a
/// prohibition the street is making; this red only reports that a limit
/// somebody set has been passed, which is a fact about a clock and not an
/// opinion about a car.
///
/// The shading runs **across** the ring rather than along it. An angular
/// gradient following the arc looked like a filament in theory and like a fault
/// in practice: on a nearly full circle its dark tail meets its bright head at
/// twelve o'clock and the join reads as a break in the stroke.
struct CountdownRing: View {

    /// How much of the allowance has been used, in `0...1`.
    let progress: Double

    /// Whether the allowance is nearly gone. Urgency is shown by movement
    /// rather than by a change of colour.
    var urgent: Bool = false

    /// Whether the limit has been passed. Amber counts time down; red reports
    /// that it has run out.
    var overrun: Bool = false

    var lineWidth: CGFloat = 9
    var breathes: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How much of the ring is still lit. A passed limit shows a full ring in
    /// red rather than an empty one, because an empty ring says nothing.
    private var remaining: Double { overrun ? 1 : max(0.0001, 1 - progress) }

    /// Both stops stay bright, so no part of the arc can be mistaken for an
    /// unlit one.
    private var lit: LinearGradient {
        LinearGradient(
            colors: overrun
                ? [Kerb.overdueHot, Kerb.overdue]
                : [Kerb.amberHot, Kerb.amber],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var halo: Color { overrun ? Kerb.overdue : Kerb.amber }

    var body: some View {
        ZStack {
            // The track. Barely there, so the lit part is the only thing the
            // eye is asked to read.
            Circle()
                .stroke(Kerb.chalkFaint.opacity(0.18), lineWidth: lineWidth)

            // What is left of the allowance, in one unbroken stroke.
            Circle()
                .trim(from: 0, to: remaining)
                .stroke(lit, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(
                    color: halo.opacity(urgent || overrun ? 0.6 : 0.35),
                    radius: urgent || overrun ? 14 : 9
                )
        }
        .considerate(Kerb.Motion.track, value: progress)
        .modifier(Breathing(active: urgent && breathes && !reduceMotion))
        .accessibilityHidden(true)
    }
}

/// A slow swell, used only when an allowance is nearly used up.
///
/// It is the one thing in the interface that asks for attention rather than
/// waiting to be looked at, so it is reserved for the one moment that warrants
/// it and it stops completely when motion is reduced.
private struct Breathing: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            TimelineView(.animation(minimumInterval: 1 / 20)) { context in
                let phase = context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 2.4) / 2.4
                let swell = (sin(phase * 2 * .pi) + 1) / 2
                content
                    .scaleEffect(1 + swell * 0.022)
                    .opacity(0.82 + swell * 0.18)
            }
        } else {
            content
        }
    }
}

/// The falling number inside the ring.
///
/// The system draws the count, so it stays right without the app waking up.
/// That is what keeps it correct in a widget, on the Lock Screen and in the
/// Dynamic Island, where the app is not running at all.
///
/// Once an allowance is used up the same figure counts back the other way.
/// Overrun is stated rather than hidden, because a car past its limit is
/// exactly when somebody most needs the truth.
struct CountdownFigure: View {
    let expiry: Date?

    /// The instant the surface was drawn at. Passed in rather than read here
    /// so a widget entry and its view agree about when "now" was.
    let now: Date

    var size: CGFloat = 34

    /// Where the digits sit inside the box the figure reserves.
    ///
    /// Centred by default, because the figure's usual home is the bore of a
    /// ring and it has to stay on the ring's centre whatever it currently
    /// reads. Leading for the surfaces that set it against a left margin.
    var alignment: Alignment = .center

    /// Scales with the reader's text size. The hero numbers were the one place
    /// in the app still pinned to a fixed point size.
    @ScaledMetric(relativeTo: .largeTitle) private var scale: CGFloat = 1

    private var pointSize: CGFloat { size * scale }

    private var face: Font {
        .system(size: pointSize, weight: .semibold, design: .rounded)
    }

    /// The widest shape this particular count can reach before it is next
    /// redrawn, which is what the figure reserves room for.
    ///
    /// The system keeps drawing the count long after the app or the widget
    /// stopped running, so the string changes width under a view that is not
    /// being laid out again: `1:00:00` falls to `59:59` and loses a whole
    /// column. Anything centred on it — the bore of a ring, the word beneath —
    /// jumps sideways at that moment. Reserving the longest form holds it
    /// still, and measuring that form from this count rather than assuming the
    /// worst means a fifteen minute limit is not given room for an hours
    /// column it will never use.
    private var widest: String {
        guard let expiry else { return "0:00" }
        let remaining = expiry.timeIntervalSince(now)
        // Past its limit the figure counts upwards, and it has all the time in
        // the world to reach an hour.
        return remaining >= 3600 || remaining <= 0 ? "0:00:00" : "00:00"
    }

    var body: some View {
        // The sizer is the thing being laid out and the count is drawn over
        // it. A `.background` cannot do this job: a background is given the
        // size of the content it sits behind and never widens it, so the
        // reserved width this used to ask for was never actually reserved.
        Text(widest)
            .hidden()
            .overlay(alignment: alignment) { figure }
            .font(face)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .multilineTextAlignment(alignment == .leading ? .leading : .center)
    }

    private var figure: some View {
        Group {
            if let expiry {
                if expiry > now {
                    Text(timerInterval: now...expiry, countsDown: true)
                        .foregroundStyle(Kerb.chalk)
                } else {
                    // Counting up from the moment it ran out. The upper bound
                    // is far enough away that it is never reached.
                    Text(
                        timerInterval: expiry...expiry.addingTimeInterval(60 * 60 * 24 * 7),
                        countsDown: false
                    )
                    .foregroundStyle(Kerb.overdue)
                }
            } else {
                Text("—").foregroundStyle(Kerb.chalkDim)
            }
        }
    }
}

/// A plate reduced to its first line, for the places a full plate will not
/// fit: a widget, the Dynamic Island, a row in a list.
///
/// It keeps the enamel ground and the coloured border, so it still reads as
/// the object it came from rather than as a coloured label.
struct PlateBadge: View {
    let text: String
    let tone: PlateTone
    var size: CGFloat = 20

    var body: some View {
        Text(text)
            .font(Kerb.plateFace(size))
            .foregroundStyle(tone.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, size * 0.42)
            .padding(.vertical, size * 0.2)
            .background(Kerb.plate, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .strokeBorder(tone.ink, lineWidth: max(1.5, size * 0.1))
                    .padding(size * 0.09)
            }
            .accessibilityLabel(text)
    }
}

// MARK: - Reading a limit for display

/// What a countdown needs to draw itself, worked out in one place so the app,
/// the widgets and the Live Activity cannot disagree.
struct CountdownReading {
    var expiry: Date?
    var progress: Double
    var urgent: Bool
    var overrun: Bool

    /// Under this much left, the ring starts to breathe — but never for more
    /// than the last quarter of the allowance. A quarter of an hour is the end
    /// of a two hour stay and the whole of a fifteen minute one, and a ring
    /// that breathes from the moment it is set is just a ring that breathes.
    static let urgentSeconds: TimeInterval = 15 * 60

    init(limit: ParkingLimit, now: Date) {
        expiry = limit.expiry
        progress = limit.progress(at: now) ?? 0
        let remaining = limit.remaining(at: now)
        // At the exact instant a limit runs out it has run out. Treating that
        // as "still has time left" is what let a passed limit keep saying
        // "left" while the figure beside it counted upwards.
        overrun = (remaining ?? 1) <= 0

        let threshold = min(Self.urgentSeconds, (limit.span ?? 0) * 0.25)
        urgent = remaining.map { $0 >= 0 && $0 <= threshold } ?? false
    }
}
