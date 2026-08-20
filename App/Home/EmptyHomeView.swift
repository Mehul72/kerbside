import SwiftUI

/// Home with no car saved.
///
/// The first screen anybody sees, and the one with the least to show: no car,
/// no sign, no clock running. What it has to do is say what the app is for and
/// put one target under the thumb, without looking like a screen whose content
/// failed to load.
struct EmptyHomeView: View {
    @ObservedObject var controller: ParkingController
    @Binding var route: HomeView.Route?

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    KerbsideMark().entering(0)

                    Spacer(minLength: 20).frame(maxHeight: 44)

                    RestingDial().entering(1)

                    Spacer(minLength: 26).frame(maxHeight: 40)

                    VStack(spacing: 9) {
                        Text("No car saved")
                            .font(Kerb.voice(.title3))
                            .foregroundStyle(Kerb.chalk)
                        Text(
                            "Save the spot and Kerbside points you back to it, and tells "
                                + "you before your time runs out."
                        )
                        .font(Kerb.voice(.subheadline))
                        .foregroundStyle(Kerb.chalkDim)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 292)
                    }
                    .entering(2)

                    Spacer(minLength: 30).frame(maxHeight: 72)

                    VStack(spacing: 18) {
                        Button(action: { Task { await controller.park() } }) {
                            Text(controller.isSaving ? "Saving" : "Park here")
                        }
                        .buttonStyle(PlateButton(kind: .enamel))
                        .accessibilityIdentifier("park")
                        .disabled(controller.isSaving)

                        // Deliberately not a second full-width button. The sign
                        // can just as well be read after the car is saved, so
                        // it does not compete with saving it.
                        Button {
                            route = .reader
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: "viewfinder")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Read a sign first")
                                    .font(Kerb.ui(.subheadline, weight: .medium))
                            }
                            .foregroundStyle(Kerb.chalkDim)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("read-sign")
                    }
                    .frame(maxWidth: 300)
                    .entering(3)

                    if controller.location.isDenied {
                        Text(
                            "Location is off for Kerbside, so a spot will remember the "
                                + "time and the sign but not the place."
                        )
                        .kerbCaption(Kerb.chalkFaint, style: .footnote)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 290)
                        .padding(.top, 18)
                    }

                    Spacer(minLength: 28)

                    if !controller.record.past.isEmpty {
                        pastSpots.entering(4)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                .padding(.horizontal, 28)
                .padding(.top, 10)
                .padding(.bottom, 18)
            }
            .scrollIndicators(.hidden)
        }
    }

    /// The footer. A centred word with no affordance reads as a caption, so it
    /// is a row with somewhere to go.
    private var pastSpots: some View {
        Button { route = .past } label: {
            HStack(spacing: 10) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Kerb.chalkFaint)
                Text("Past spots")
                    .kerbCaption(Kerb.chalkDim, style: .subheadline, weight: .medium)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Kerb.chalkFaint)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .kerbCard(.quiet)
        }
        .kerbPressable()
        .accessibilityIdentifier("past")
    }
}

/// The app's name, small, at the top of its first screen.
///
/// The screen used to carry no identification at all, which is a strange thing
/// for the first thing a person opens. This is the wordmark reduced to a chip:
/// enamel and green, because those are Kerbside's own colours, at a size that
/// introduces the app rather than competing with the one button on the screen.
private struct KerbsideMark: View {
    var body: some View {
        HStack(spacing: 7) {
            Text("Kerbside")
                .font(Kerb.plateFace(15))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(Kerb.signGreen)
            Text("NSW")
                .font(.system(size: 8, weight: .semibold).width(.expanded))
                .tracking(1.6)
                .foregroundStyle(Kerb.signGreen.opacity(0.7))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(Kerb.plate, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Kerb.signGreen, lineWidth: 1.5)
                .padding(2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Kerbside")
    }
}

/// The app's instrument, with nothing in it yet.
///
/// This screen used to lead with a green enamel plate bolted to a pole, which
/// made a parking sign the largest object on the one screen that has neither a
/// sign nor a car. The subject here is the car, and the instrument the app
/// reads it with is the ring that counts a limit down, so the empty state is
/// that same ring at the same size, unlit. Parking lights it.
///
/// Unlit is not the same as absent, though, and a plain grey stroke around a
/// small glyph read as a picture that had failed to load. So it is dressed as
/// an instrument at rest: the countdown's own track, a dial marked around it, a
/// trace of the app's amber so its colour appears somewhere on its first
/// screen, and the slowest possible breath to say it is waiting rather than
/// broken.
private struct RestingDial: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The same diameter the countdown takes once there is one, so the empty
    /// screen is the parked screen with its instrument unlit rather than a
    /// different composition.
    private let side: CGFloat = 244
    private let stroke: CGFloat = 13

    var body: some View {
        ZStack {
            // Barely there. The app's colour, present but not yet meaning
            // anything, because nothing is being counted.
            HeroGlow(strength: 0.075)

            Circle()
                .stroke(Kerb.chalkFaint.opacity(0.18), lineWidth: stroke)

            // Twelve marks outside the track. A bare circle is a shape; a
            // circle with a scale on it is an instrument.
            ForEach(0..<12) { mark in
                Capsule()
                    .fill(Kerb.chalkFaint.opacity(mark % 3 == 0 ? 0.65 : 0.32))
                    .frame(width: 1.5, height: mark % 3 == 0 ? 8 : 4.5)
                    .offset(y: -side * 0.5 - 6)
                    .rotationEffect(.degrees(Double(mark) * 30))
            }

            Image(systemName: "car.fill")
                .font(.system(size: 68, weight: .regular))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Kerb.chalkDim, Kerb.chalkFaint],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .frame(width: side, height: side)
        .modifier(Waiting(active: !reduceMotion))
        .accessibilityHidden(true)
    }
}

/// A breath so slow it is felt rather than seen.
///
/// The countdown ring breathes when an allowance is nearly gone, which is a
/// warning. This is the opposite end of the same idea: an instrument idling.
/// Six seconds a cycle and two percent of scale, which is enough to stop the
/// screen looking frozen and not enough to draw the eye off the button.
private struct Waiting: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            TimelineView(.animation(minimumInterval: 1 / 12)) { context in
                let phase = context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 6) / 6
                let swell = (sin(phase * 2 * .pi) + 1) / 2
                content
                    .scaleEffect(1 + swell * 0.018)
                    .opacity(0.88 + swell * 0.12)
            }
        } else {
            content
        }
    }
}
