import SignKit
import SwiftUI

/// One physical plate, drawn the way it is bolted to the pole.
///
/// A plate carries the words that were on the sign. Kerbside's reading of
/// those words is set elsewhere, in a different face, so that the two voices
/// can never be confused for one another.
struct Plate<Content: View>: View {
    let tone: PlateTone
    /// Whether this plate's rule covers the current instant, which lights it.
    var lit: Bool = true
    /// Whether this plate's rule is outside its hours. Held apart from `lit`
    /// on purpose: dimming says "not now", and only a panel that was read has
    /// hours to be outside of. An unread panel is neither lit nor dimmed, so
    /// it stands at full strength beside the ones that parsed.
    var dimmed: Bool = false
    /// Unread plates are outlined rather than ruled, which says the boundary
    /// of the panel is known but its contents are not.
    var dashed: Bool = false
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Kerb.plateCorner, style: .continuous)
    }

    var body: some View {
        content()
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
            .background(Kerb.plate)
            .overlay(border)
            .clipShape(shape)
            .overlay {
                if lit, !reduceMotion {
                    Sheen()
                        .clipShape(shape)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: Kerb.plateWidth)
            .shadow(color: .black.opacity(0.55), radius: 18, y: 10)
            .shadow(
                color: lit ? Color.white.opacity(0.16) : .clear,
                radius: 26
            )
            .saturation(dimmed ? 0.5 : 1)
            .opacity(dimmed ? 0.44 : 1)
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: Kerb.plateCorner - Kerb.plateInset + 3, style: .continuous)
            .strokeBorder(
                tone.ink,
                style: StrokeStyle(
                    lineWidth: Kerb.plateBorderWidth,
                    dash: dashed ? [8, 6] : []
                )
            )
            .padding(Kerb.plateInset)
    }
}

/// A slow specular pass, as though a headlight crossed the sign.
///
/// Retroreflective plates are the reason the ground of this app is dark, and
/// this is the one piece of ambient motion in the interface. It marks the
/// panel in force now, and it stops entirely when motion is reduced.
private struct Sheen: View {
    var body: some View {
        TimelineView(.animation) { context in
            GeometryReader { geometry in
                let width = geometry.size.width
                let cycle = 7.0
                let elapsed = context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: cycle)
                // Crosses in the first third of the cycle, then rests, so the
                // plate is still most of the time.
                let travel = min(elapsed / (cycle * 0.32), 1)
                let eased = travel * travel * (3 - 2 * travel)

                LinearGradient(
                    colors: [.clear, .white.opacity(0.5), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: width * 0.42)
                .rotationEffect(.degrees(22))
                .offset(x: -width * 0.7 + eased * width * 1.9)
                .blendMode(.plusLighter)
            }
        }
    }
}

// MARK: - Arrows

/// The arrow as it is painted on a parking plate: a plain shaft with a
/// triangular head, naming the stretch of kerb the panel governs.
struct SignArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let headStart = rect.minX + rect.width * 0.5
        let shaftTop = rect.minY + rect.height * 0.33
        let shaftHeight = rect.height * 0.34

        path.addRect(
            CGRect(
                x: rect.minX,
                y: shaftTop,
                width: headStart - rect.minX,
                height: shaftHeight
            )
        )
        path.move(to: CGPoint(x: headStart, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: headStart, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// The arrow row on a plate. A panel that named no direction draws nothing —
/// the absence is reported in words underneath rather than invented here.
struct ArrowRow: View {
    let direction: Direction
    let ink: Color

    var body: some View {
        HStack(spacing: 14) {
            switch direction {
            case .left:
                arrow(pointingLeft: true)
            case .right:
                arrow(pointingLeft: false)
            case .both:
                arrow(pointingLeft: true)
                arrow(pointingLeft: false)
            case .unspecified:
                EmptyView()
            }
        }
        .accessibilityHidden(true)
    }

    private func arrow(pointingLeft: Bool) -> some View {
        SignArrow()
            .fill(ink)
            .frame(width: 44, height: 22)
            .scaleEffect(x: pointingLeft ? -1 : 1)
    }
}

// MARK: - Panels

/// A plate whose words parsed.
struct PanelPlate: View {
    let panel: Panel
    var lit: Bool

    private var lines: [String] {
        panel.rawText
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        Plate(tone: PlateTone(panel.restriction), lit: lit, dimmed: !lit) {
            VStack(spacing: 8) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    Text(line)
                        .font(Kerb.plateFace(size(of: line, at: index)))
                        .tracking(0.5)
                        .foregroundStyle(PlateTone(panel.restriction).ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.45)
                }

                if panel.direction != .unspecified {
                    ArrowRow(
                        direction: panel.direction,
                        ink: PlateTone(panel.restriction).ink
                    )
                    .padding(.top, 2)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sign panel reading: \(lines.joined(separator: ", "))")
    }

    /// The first line of a plate is its restriction and is set largest, the
    /// way it is painted. A very short one such as `1P` is set larger still.
    private func size(of line: String, at index: Int) -> CGFloat {
        guard index == 0 else { return 21 }
        return line.count <= 3 ? 50 : 27
    }
}

/// A plate whose words did not parse.
///
/// It is the same width, in the same place in the stack, at full strength.
/// The only difference is that its text is set in monospace and its border is
/// broken, both of which say the contents were not understood rather than
/// that they matter less.
struct UnknownPlate: View {
    let unknown: Unknown

    private var lines: [String] {
        unknown.rawText
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        Plate(tone: .unread, lit: false, dimmed: false, dashed: true) {
            VStack(spacing: 10) {
                Text("Not read")
                    .kerbLabel(Kerb.chalkFaint, style: .caption2)

                if lines.isEmpty {
                    Text("No text")
                        .font(Kerb.data(13))
                        .foregroundStyle(Kerb.chalkFaint)
                } else {
                    VStack(spacing: 4) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(Kerb.data(13))
                                .foregroundStyle(Color.black.opacity(0.72))
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Panel not read. \(Wording.describe(unknown.reason)) "
                + (lines.isEmpty ? "No text." : "Text on the sign: \(lines.joined(separator: ", "))")
        )
    }
}
