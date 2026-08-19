import SwiftUI

/// How much presence a surface has.
///
/// A screen where every card is drawn identically has no hierarchy inside its
/// sections: the row you act on looks exactly like the note you ignore. These
/// are the three weights anything containing gets to be.
enum KerbWeight {
    /// The row this section exists for.
    case primary
    /// Supporting, and most things.
    case secondary
    /// Incidental — a note, a field, something you add if you feel like it.
    case quiet

    /// The three weights were originally close enough together that a screen
    /// of stacked cards read as one grey column: the row you act on looked
    /// like the note you ignore. They are spread much further apart now, so
    /// the order is legible at a glance rather than on inspection.
    var fill: (top: Double, bottom: Double) {
        switch self {
        case .primary: (0.185, 0.075)
        case .secondary: (0.075, 0.03)
        case .quiet: (0.028, 0.012)
        }
    }

    var edge: (top: Double, bottom: Double) {
        switch self {
        case .primary: (0.42, 0.09)
        case .secondary: (0.16, 0.04)
        case .quiet: (0.075, 0.02)
        }
    }

    var shadow: Double {
        switch self {
        case .primary: 0.5
        case .secondary: 0.2
        case .quiet: 0
        }
    }
}

/// The surfaces things sit on.
///
/// Everything here is one idea: light falls from above. A card catches a
/// hairline of it along its top edge and loses it towards the bottom, which is
/// enough to make a surface read as a raised object rather than as a hole cut
/// in the background. The tint is cool, to match the ground.
extension View {

    func kerbCard(
        _ weight: KerbWeight = .secondary,
        radius: CGFloat = 18,
        dashed: Bool = false,
        tint: Color? = nil
    ) -> some View {
        modifier(KerbCard(weight: weight, radius: radius, dashed: dashed, tint: tint))
    }

    /// Presses inwards a little. Used with `kerbCard` on anything that acts.
    func kerbPressable() -> some View {
        buttonStyle(PressableCard())
    }
}

private struct KerbCard: ViewModifier {
    let weight: KerbWeight
    let radius: CGFloat
    let dashed: Bool
    let tint: Color?

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    private var base: Color { tint ?? Kerb.slate }
    private var line: Color { tint ?? Kerb.chalk }

    func body(content: Content) -> some View {
        let fill = weight.fill
        let edge = weight.edge
        let tinted = tint != nil

        content
            .background {
                shape.fill(
                    LinearGradient(
                        // A tint says "this one is chosen", and it says it
                        // through its lit edge. The fill behind it is held at
                        // one modest value rather than scaled off the weight:
                        // a tinted card at `primary` weight came out a solid
                        // amber-brown slab that read as a filled button, and
                        // the colour stopped meaning selected and started
                        // meaning loud.
                        colors: tinted
                            ? [base.opacity(0.13), base.opacity(0.05)]
                            : [base.opacity(fill.top), base.opacity(fill.bottom)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .overlay {
                // The lit edge. Brightest along the top, gone by the bottom,
                // which is the whole of the illusion.
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            line.opacity(tinted ? 0.5 : edge.top),
                            line.opacity(edge.bottom),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    style: StrokeStyle(lineWidth: 1, dash: dashed ? [6, 5] : [])
                )
            }
            .clipShape(shape)
            .shadow(color: .black.opacity(weight.shadow), radius: 12, y: 5)
    }
}

private struct PressableCard: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.976 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// A rule that fades out at both ends.
///
/// A divider drawn edge to edge cuts a screen in half. One that arrives and
/// leaves separates without severing.
struct Hairline: View {
    var body: some View {
        LinearGradient(
            colors: [.clear, Kerb.chalkFaint.opacity(0.45), .clear],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 1)
        .accessibilityHidden(true)
    }
}

/// The light the countdown throws onto the ground behind it.
///
/// The app's one hero element is a ring burning down, and a light source with
/// nothing to fall on does not read as a light source. Kept very low so it
/// suggests depth without becoming a glow effect in its own right.
struct HeroGlow: View {
    var tint: Color = Kerb.amber
    var strength: Double = 0.16

    var body: some View {
        RadialGradient(
            colors: [tint.opacity(strength), tint.opacity(strength * 0.35), .clear],
            center: .center,
            startRadius: 0,
            endRadius: 260
        )
        .blur(radius: 40)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
