import ParkKit
import SwiftUI

/// The ring around a countdown.
///
/// It depletes as the allowance is used, and it is amber throughout, because
/// amber is this app's colour for time. It never turns green or red: those two
/// belong to the plate and mean what the plate means. A ring that turned red
/// would be the app forming an opinion, and it does not have one.
struct CountdownRing: View {

    /// How much of the allowance has been used, in `0...1`.
    let progress: Double

    /// Whether the allowance is nearly gone. Urgency is shown by movement
    /// rather than by a change of colour.
    var urgent: Bool = false

    var lineWidth: CGFloat = 9
    var breathes: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(Kerb.chalkFaint.opacity(0.25), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: max(0.001, 1 - progress))
                .stroke(
                    Kerb.amber,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: Kerb.amber.opacity(0.5), radius: urgent ? 10 : 5)
                .considerate(Kerb.Motion.track, value: progress)
        }
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

    var body: some View {
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
                    .foregroundStyle(Kerb.amber)
                }
            } else {
                Text("—").foregroundStyle(Kerb.chalkDim)
            }
        }
        .font(.system(size: size, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.5)
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

    /// Under this much left, the ring starts to breathe.
    static let urgentSeconds: TimeInterval = 15 * 60

    init(limit: ParkingLimit, now: Date) {
        expiry = limit.expiry
        progress = limit.progress(at: now) ?? 0
        let remaining = limit.remaining(at: now)
        overrun = (remaining ?? 1) < 0
        urgent = remaining.map { $0 >= 0 && $0 <= Self.urgentSeconds } ?? false
    }
}
