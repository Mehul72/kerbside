import SwiftUI

/// The surfaces things sit on.
///
/// A flat panel of five percent white on black is what a dark interface looks
/// like before anybody has thought about it. Everything here is one idea: light
/// falls from above. A card catches a hairline of it along its top edge and
/// loses it towards the bottom, which is enough to make a surface read as a
/// raised object rather than as a hole cut in the background.
extension View {

    /// A raised panel. The default for anything tappable or containing.
    func kerbCard(
        radius: CGFloat = 14,
        dashed: Bool = false,
        tint: Color? = nil
    ) -> some View {
        modifier(KerbCard(radius: radius, dashed: dashed, tint: tint))
    }

    /// Presses inwards a little. Used with `kerbCard` on anything that acts.
    func kerbPressable() -> some View {
        buttonStyle(PressableCard())
    }
}

private struct KerbCard: ViewModifier {
    let radius: CGFloat
    let dashed: Bool
    let tint: Color?

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    func body(content: Content) -> some View {
        content
            .background {
                shape.fill(
                    LinearGradient(
                        colors: [
                            (tint ?? Color.white).opacity(tint == nil ? 0.075 : 0.11),
                            (tint ?? Color.white).opacity(tint == nil ? 0.028 : 0.04),
                        ],
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
                            (tint ?? Kerb.chalk).opacity(tint == nil ? 0.22 : 0.5),
                            (tint ?? Kerb.chalk).opacity(0.05),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    style: StrokeStyle(lineWidth: 1, dash: dashed ? [6, 5] : [])
                )
            }
            .clipShape(shape)
            .shadow(color: .black.opacity(0.35), radius: 12, y: 5)
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
/// The app's one hero element is a burning-down ring, and a light source with
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
