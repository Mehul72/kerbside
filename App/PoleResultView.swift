import SignKit
import SwiftUI
import UIKit

/// The reading, drawn as the pole it came off.
///
/// Panels are stacked in the order they appear on the sign rather than sorted
/// into what is in force and what is not, because that order is information
/// the photograph actually contains. Which rule applies now is said by
/// lighting one plate, not by rearranging them.
struct PoleResultView: View {
    let evaluation: Evaluation
    let plates: [PlateItem]
    let photo: UIImage?
    let timeZone: TimeZone

    @State private var showingOnPhoto = false
    @State private var homeFrames: [Int: CGRect] = [:]
    @State private var settled = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let stageSpace = "pole.stage"

    /// The index of the plate that owns the next change, so the marker is
    /// drawn against the panel it belongs to instead of in a section of its
    /// own. Matched once, so two identical panels do not both claim it.
    private var changeIndex: Int? {
        guard let change = evaluation.nextChange else { return nil }
        return plates.first { item in
            if case .panel(let panel) = item.result { return panel == change.panel }
            return false
        }?.id
    }

    private var canTrace: Bool {
        photo != nil && plates.contains { $0.sourceBox != nil }
    }

    var body: some View {
        GeometryReader { stage in
            ZStack(alignment: .top) {
                Backdrop(
                    image: photo,
                    blur: showingOnPhoto ? 0 : 26,
                    dim: showingOnPhoto ? 0.3 : 0.82
                )

                ScrollView {
                    VStack(spacing: 0) {
                        pole(in: stage.size)
                        footer
                    }
                }
                .scrollDisabled(showingOnPhoto)
            }
            .coordinateSpace(name: Self.stageSpace)
        }
        .safeAreaInset(edge: .top, spacing: 0) { nowBar }
        .onPreferenceChange(PlateFrameKey.self) { homeFrames = $0 }
        .onAppear {
            guard !settled else { return }
            settled = true
        }
    }

    // MARK: - The pole

    private func pole(in stage: CGSize) -> some View {
        ZStack(alignment: .top) {
            PoleSpine()
                .frame(maxHeight: .infinity)
                .opacity(showingOnPhoto ? 0 : 1)

            VStack(spacing: Kerb.plateGap) {
                ForEach(plates) { item in
                    slot(for: item, in: stage)
                }
            }
            .padding(.vertical, 40)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func slot(for item: PlateItem, in stage: CGSize) -> some View {
        let active = isActive(item)
        let shift = displacement(for: item, in: stage)

        return VStack(spacing: 12) {
            if active {
                Text("In force now")
                    .kerbLabel(Kerb.chalk, style: .caption2)
                    .opacity(showingOnPhoto ? 0 : 1)
            }

            plate(for: item, active: active)
                .background(measure(item.id))
                .scaleEffect(shift.scale)
                .offset(shift.offset)

            reading(for: item)
                .opacity(showingOnPhoto ? 0 : 1)

            if item.id == changeIndex, let change = evaluation.nextChange {
                ChangeMarker(change: change, timeZone: timeZone)
                    .opacity(showingOnPhoto ? 0 : 1)
            }
        }
        .offset(y: settled || reduceMotion ? 0 : 26)
        .opacity(settled || reduceMotion ? 1 : 0)
        .animation(
            reduceMotion
                ? nil
                : .spring(response: 0.62, dampingFraction: 0.78)
                    .delay(Double(item.id) * 0.075),
            value: settled
        )
        .animation(.spring(response: 0.55, dampingFraction: 0.82), value: showingOnPhoto)
    }

    @ViewBuilder
    private func plate(for item: PlateItem, active: Bool) -> some View {
        switch item.result {
        case .panel(let panel):
            PanelPlate(panel: panel, lit: active)
        case .unknown(let unknown):
            UnknownPlate(unknown: unknown)
        }
    }

    /// Kerbside's own account of the panel, set in the serif so it reads as
    /// the app speaking rather than as more of the sign.
    @ViewBuilder
    private func reading(for item: PlateItem) -> some View {
        switch item.result {
        case .panel(let panel):
            VStack(spacing: 5) {
                Text(Wording.describe(panel))
                    .font(Kerb.voice())
                    .foregroundStyle(Kerb.chalk)
                if let note = Wording.missingDirectionNote(panel.direction) {
                    Text(note)
                        .font(Kerb.voice(.footnote))
                        .foregroundStyle(Kerb.chalkDim)
                }
            }
            .multilineTextAlignment(.center)
            .frame(width: Kerb.plateWidth + 24)

        case .unknown(let unknown):
            Text(Wording.describe(unknown.reason))
                .font(Kerb.voice(.footnote))
                .foregroundStyle(Kerb.chalkDim)
                .multilineTextAlignment(.center)
                .frame(width: Kerb.plateWidth + 24)
        }
    }

    // MARK: - Now

    private var nowBar: some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .leading, spacing: 6) {
                adaptiveRow {
                    Text("Now in Sydney")
                        .kerbLabel()
                    if !dynamicTypeSize.isAccessibilitySize {
                        Spacer(minLength: 12)
                    }
                    if canTrace {
                        traceButton
                    }
                }

                adaptiveRow {
                    Text(Self.clock(context.date, in: timeZone))
                        .font(
                            .system(.title, design: .default, weight: .semibold)
                                .width(.expanded)
                        )
                        .foregroundStyle(Kerb.chalk)
                    Text(Self.day(context.date, in: timeZone))
                        .kerbLabel(Kerb.chalkDim)
                    if !dynamicTypeSize.isAccessibilitySize {
                        Spacer(minLength: 0)
                    }
                }

                if evaluation.active.isEmpty {
                    Text("No panel covers this time.")
                        .font(Kerb.voice(.footnote))
                        .foregroundStyle(Kerb.chalkDim)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 14)
            .background(
                LinearGradient(
                    colors: [Kerb.asphalt, Kerb.asphalt.opacity(0.92), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea(edges: .top)
            )
        }
    }

    private var traceButton: some View {
        Button {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                showingOnPhoto.toggle()
            }
        } label: {
            Label(
                showingOnPhoto ? "Back to pole" : "Show on photo",
                systemImage: showingOnPhoto ? "arrow.uturn.backward" : "viewfinder"
            )
            .kerbLabel(Kerb.amber, style: .caption2)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .overlay(
                Capsule().strokeBorder(Kerb.amber.opacity(0.55), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 10) {
            Rectangle()
                .fill(Kerb.chalkFaint.opacity(0.35))
                .frame(width: 40, height: 1)

            Text(tally)
                .kerbLabel(Kerb.chalkFaint, style: .caption2)

            Text("Kerbside reports what each panel says. It does not tell you whether you may park.")
                .font(Kerb.voice(.footnote))
                .foregroundStyle(Kerb.chalkFaint)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .padding(.top, 10)
        // Clears the action row pinned to the bottom of the screen.
        .padding(.bottom, 130)
        .opacity(showingOnPhoto ? 0 : 1)
    }

    private var tally: String {
        let read = plates.count - evaluation.unknowns.count
        let panels = read == 1 ? "1 panel read" : "\(read) panels read"
        guard !evaluation.unknowns.isEmpty else { return panels }
        return "\(panels) · \(evaluation.unknowns.count) not read"
    }

    // MARK: - Provenance

    /// How far a plate must travel to sit back over the part of the photograph
    /// it was read from.
    private func displacement(
        for item: PlateItem,
        in stage: CGSize
    ) -> (offset: CGSize, scale: CGFloat) {
        guard showingOnPhoto,
              let photo,
              let box = item.sourceBox,
              let home = homeFrames[item.id],
              home.width > 0,
              let target = placement(of: box, imageSize: photo.size, in: stage)
        else { return (.zero, 1) }

        let scale = min(max(target.width / home.width, 0.1), 2.5)
        return (
            CGSize(
                width: target.midX - home.midX,
                height: target.midY - home.midY
            ),
            scale
        )
    }

    private func measure(_ id: Int) -> some View {
        GeometryReader { geometry in
            Color.clear.preference(
                key: PlateFrameKey.self,
                value: [id: geometry.frame(in: .named(Self.stageSpace))]
            )
        }
    }

    private func isActive(_ item: PlateItem) -> Bool {
        guard case .panel(let panel) = item.result else { return false }
        return evaluation.active.contains(panel)
    }

    @ViewBuilder
    private func adaptiveRow<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8, content: content)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 10, content: content)
        }
    }

    // MARK: - Formatting

    private static func clock(_ date: Date, in zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = zone
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    private static func day(_ date: Date, in zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = zone
        formatter.dateFormat = "EEE d MMM"
        return formatter.string(from: date)
    }
}

/// The layout position of each plate on the pole, used to work out how far it
/// has to move to return to the photograph.
private struct PlateFrameKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] { [:] }

    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// When this panel's rule next begins or ends, hung off the plate it belongs
/// to. Amber is the interface's only accent and it is spent entirely here, on
/// time.
private struct ChangeMarker: View {
    let change: Change
    let timeZone: TimeZone

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(spacing: 7) {
                Rectangle()
                    .fill(Kerb.amber.opacity(0.7))
                    .frame(width: 1.5, height: 18)

                Text("\(change.kind == .begins ? "Begins" : "Ends") \(clock)")
                    .kerbLabel(Kerb.amber, style: .caption2)

                if let remaining = remaining(from: context.date) {
                    Text(remaining)
                        .font(Kerb.voice(.footnote))
                        .foregroundStyle(Kerb.chalkDim)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var clock: String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: change.at)
    }

    private func remaining(from now: Date) -> String? {
        let seconds = change.at.timeIntervalSince(now)
        guard seconds > 0 else { return nil }
        let minutes = Int(seconds / 60)
        switch minutes {
        case 0: return "in under a minute"
        case 1: return "in 1 minute"
        case 2..<90: return "in \(minutes) minutes"
        default:
            let hours = minutes / 60
            return hours == 1 ? "in about an hour" : "in about \(hours) hours"
        }
    }
}
