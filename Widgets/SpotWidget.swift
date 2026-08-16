import ParkKit
import SignKit
import SwiftUI
import WidgetKit

/// What the widget shows at one instant.
struct SpotEntry: TimelineEntry {
    var date: Date
    var spot: ParkingSpot?

    /// False when the App Group is unavailable, which is the one failure a
    /// widget can neither fix nor hide. It says so rather than pretending no
    /// car is parked.
    var shared: Bool = true
}

struct SpotProvider: TimelineProvider {

    func placeholder(in context: Context) -> SpotEntry {
        SpotEntry(date: .now, spot: Self.example)
    }

    func getSnapshot(in context: Context, completion: @escaping (SpotEntry) -> Void) {
        completion(entry(at: .now))
    }

    /// How many times the ring is redrawn across an allowance.
    ///
    /// A timeline may carry many entries for the cost of one refresh — the
    /// budget is on how often the provider is asked, not on how much it
    /// returns — so the ring can be stepped finely without waking the app.
    private static let steps = 60

    /// The falling number redraws itself, because the system draws it from an
    /// expiry. The ring does not: it is a shape, and a shape only changes when
    /// the system moves to another entry. Handing over one entry would freeze
    /// the ring at the moment the timeline was built and let it drift further
    /// from the truth every minute, so the allowance is stepped across.
    func getTimeline(in context: Context, completion: @escaping (Timeline<SpotEntry>) -> Void) {
        let now = Date.now
        let current = entry(at: now)
        var dates: [Date] = []

        if let expiry = current.spot?.limit.expiry {
            let span = current.spot?.limit.span ?? 0
            // Never finer than a minute: a ring that moves less than a
            // sixtieth of a turn is not worth an entry.
            let step = max(60, span / Double(Self.steps))
            var at = now.addingTimeInterval(step)
            while at < expiry, dates.count < Self.steps {
                dates.append(at)
                at = at.addingTimeInterval(step)
            }
            // The moment it runs out, when the figure turns and counts up.
            if expiry > now { dates.append(expiry) }
        }
        // A backstop, so a widget left alone all day still refreshes.
        dates.append(now.addingTimeInterval(60 * 60))

        let entries = [current] + dates.sorted().map { entry(at: $0) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func entry(at date: Date) -> SpotEntry {
        guard SharedContainer.isShared else {
            return SpotEntry(date: date, spot: nil, shared: false)
        }
        return SpotEntry(date: date, spot: SharedContainer.store.loadOrEmpty().active)
    }

    static let example = ParkingSpot(
        parkedAt: .now.addingTimeInterval(-45 * 60),
        coordinate: Coordinate(latitude: -33.8688, longitude: 151.2093, accuracy: 8),
        sign: Sign(
            panels: [
                .panel(
                    Panel(
                        restriction: .timeLimited(minutes: 120),
                        rawText: "2P\n8.30AM - 6PM\nMON - FRI"
                    )
                )
            ]
        ),
        limit: .expires(at: .now.addingTimeInterval(75 * 60), source: .sign(minutes: 120))
    )
}

struct SpotWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "au.kerbside.spot", provider: SpotProvider()) { entry in
            SpotWidgetView(entry: entry)
                .containerBackground(Kerb.asphalt, for: .widget)
        }
        .configurationDisplayName("Your car")
        .description("Where you left it and what the sign above it said.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
        ])
    }
}

struct SpotWidgetView: View {
    let entry: SpotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            case .accessoryInline: inline
            case .systemMedium: medium
            default: small
            }
        }
        .widgetURL(URL(string: "kerbside://spot"))
    }

    private var reading: CountdownReading? {
        entry.spot.map { CountdownReading(limit: $0.limit, now: entry.date) }
    }

    private var headline: String {
        guard let panel = governing else { return "PARKED" }
        return ParkWording.plateHeadline(panel)
    }

    /// The rule in force now speaks for the widget; failing that, the first
    /// panel that parsed.
    private var governing: Panel? {
        guard let spot = entry.spot, let sign = spot.sign else { return nil }
        let active = spot.evaluation(at: entry.date, in: SharedContainer.timeZone)?.active
        return active?.first ?? sign.parsedPanels.first
    }

    private var tone: PlateTone {
        guard let panel = governing else { return .unread }
        return PlateTone(panel.restriction)
    }

    // MARK: - Home Screen

    private var small: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let spot = entry.spot, let reading {
                HStack {
                    PlateBadge(text: headline, tone: tone, size: 15)
                    Spacer(minLength: 0)
                }

                Spacer(minLength: 0)

                CountdownFigure(expiry: reading.expiry, now: entry.date, size: 30)
                Text(caption(for: spot, reading: reading))
                    .font(Kerb.voice(.caption2))
                    .foregroundStyle(Kerb.chalkDim)
                    .lineLimit(2)
            } else {
                empty
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var medium: some View {
        HStack(spacing: 16) {
            if let spot = entry.spot, let reading {
                ZStack {
                    CountdownRing(progress: reading.progress, urgent: reading.urgent, lineWidth: 7)
                    // Held inside the ring's bore. A long figure such as
                    // 1:58:16 shrinks to fit rather than crossing the stroke.
                    CountdownFigure(expiry: reading.expiry, now: entry.date, size: 18)
                        .frame(width: 58)
                }
                .frame(width: 82, height: 82)

                VStack(alignment: .leading, spacing: 8) {
                    PlateBadge(text: headline, tone: tone, size: 17)
                    Text(ParkWording.attribution(spot.limit, in: SharedContainer.timeZone))
                        .font(Kerb.voice(.caption))
                        .foregroundStyle(Kerb.chalk)
                        .lineLimit(2)
                    Text(ParkWording.parked(spot, relativeTo: entry.date, in: SharedContainer.timeZone))
                        .kerbLabel(Kerb.chalkFaint, style: .caption2)
                }
                Spacer(minLength: 0)
            } else {
                empty
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.shared ? "No car saved" : "Widget unavailable")
                .font(Kerb.voice(.subheadline))
                .foregroundStyle(Kerb.chalk)
            Text(
                entry.shared
                    ? "Open Kerbside to save where you parked."
                    : "This build cannot share the record with its widgets."
            )
            .font(Kerb.voice(.caption2))
            .foregroundStyle(Kerb.chalkDim)
            .lineLimit(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    /// Even at this size the number says where it came from. A limit somebody
    /// set is not "on this sign", and calling it that would put words on a
    /// plate that the plate never said.
    private func caption(for spot: ParkingSpot, reading: CountdownReading) -> String {
        guard reading.expiry != nil else { return "No limit recorded" }
        if reading.overrun { return "over the recorded limit" }
        return switch spot.limit.source {
        case .sign: "left on this sign"
        case .chosen: "left on the limit you set"
        case nil: "left"
        }
    }

    // MARK: - Lock Screen

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let reading {
                Circle()
                    .trim(from: 0, to: max(0.001, 1 - reading.progress))
                    .stroke(style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(2)
                CountdownFigure(expiry: reading.expiry, now: entry.date, size: 13)
                    .foregroundStyle(.primary)
            } else {
                Image(systemName: "car")
            }
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let spot = entry.spot, let reading {
                Text(headline)
                    .font(.system(size: 13, weight: .black).width(.condensed))
                CountdownFigure(expiry: reading.expiry, now: entry.date, size: 19)
                    .foregroundStyle(.primary)
                Text(ParkWording.attribution(spot.limit, in: SharedContainer.timeZone))
                    .font(.caption2)
                    .lineLimit(1)
            } else {
                Text("No car saved").font(.headline)
                Text("Open Kerbside to save a spot.").font(.caption2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inline: some View {
        Group {
            if let reading, let expiry = reading.expiry {
                if expiry > entry.date {
                    Text("\(headline) · ") + Text(timerInterval: entry.date...expiry, countsDown: true)
                } else {
                    Text("\(headline) · limit passed")
                }
            } else if entry.spot != nil {
                Text("\(headline) · no limit recorded")
            } else {
                Text("No car saved")
            }
        }
    }
}
