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

    /// Entries are placed where the display actually changes rather than on a
    /// clock: the falling number draws itself, so the only moments worth
    /// waking for are when an allowance becomes urgent and when it runs out.
    func getTimeline(in context: Context, completion: @escaping (Timeline<SpotEntry>) -> Void) {
        let now = Date.now
        let current = entry(at: now)
        var dates: [Date] = []

        if let expiry = current.spot?.limit.expiry {
            let urgent = expiry.addingTimeInterval(-CountdownReading.urgentSeconds)
            if urgent > now { dates.append(urgent) }
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
        entry.spot.map {
            CountdownReading(limit: $0.limit, parkedAt: $0.parkedAt, now: entry.date)
        }
    }

    private var headline: String {
        guard let panel = entry.spot?.sign?.parsedPanels.first else { return "PARKED" }
        let first = panel.rawText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        return (first ?? Wording.describe(panel.restriction)).uppercased()
    }

    private var tone: PlateTone {
        guard let panel = entry.spot?.sign?.parsedPanels.first else { return .unread }
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
                    CountdownFigure(expiry: reading.expiry, now: entry.date, size: 20)
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

    private func caption(for spot: ParkingSpot, reading: CountdownReading) -> String {
        guard reading.expiry != nil else { return "No limit recorded" }
        return reading.overrun ? "over the recorded limit" : "left on this sign"
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
