import SwiftUI

/// How things move.
///
/// Kerbside's motion has one job: to say that something changed, and which
/// thing. Nothing moves for decoration. A plate that lights, a number that
/// falls, a needle that swings to a new heading — each is a change in the
/// world being reported, which is the same contract the words obey.
extension Kerb {
    enum Motion {

        /// The default: a state landing in place. Quick enough to feel
        /// answered, damped enough not to wobble.
        static let settle = Animation.spring(response: 0.38, dampingFraction: 0.84)

        /// Something arriving that was not there before, given a little more
        /// travel so the eye catches it.
        static let arrive = Animation.spring(response: 0.55, dampingFraction: 0.72)

        /// A value being corrected rather than replaced — a distance
        /// updating, a needle tracking a heading.
        static let track = Animation.easeOut(duration: 0.45)

        /// Plates enter one after another, down the pole, the way the eye
        /// reads them. Capped so a long sign does not turn into a queue.
        static func stagger(_ index: Int) -> Animation {
            arrive.delay(min(Double(index), 5) * 0.07)
        }
    }
}

extension View {

    /// Applies an animation to a value unless motion is reduced.
    ///
    /// Reduce Motion is honoured everywhere in this app, so rather than repeat
    /// the environment read at every call site the decision is made once here.
    func considerate<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(ConsiderateValue(animation: animation, value: value))
    }

    /// Fades and lifts a view in as it appears, in reading order down the
    /// pole.
    func entering(_ index: Int, active: Bool = true) -> some View {
        modifier(Entering(index: index, active: active))
    }
}

private struct ConsiderateValue<V: Equatable>: ViewModifier {
    let animation: Animation
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

private struct Entering: ViewModifier {
    let index: Int
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .blur(radius: shown ? 0 : 3)
            .onAppear {
                guard active else {
                    shown = true
                    return
                }
                if reduceMotion {
                    shown = true
                } else {
                    withAnimation(Kerb.Motion.stagger(index)) { shown = true }
                }
            }
    }
}

// MARK: - Haptics

#if canImport(UIKit)
import UIKit

/// Physical feedback, used only where the app is reporting a real change:
/// a car saved, a car collected, a rule coming into force. Never for taps
/// that merely navigate.
enum Feedback {
    @MainActor
    static func recorded() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    @MainActor
    static func changed() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    @MainActor
    static func failed() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}
#endif
