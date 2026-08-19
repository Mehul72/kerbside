import SwiftUI

/// Home with no car saved.
///
/// One thing to do, said once, and it is not reading a sign. The moment this
/// app matters is the moment somebody is walking away from their car in a
/// hurry, so saving the spot is a single large target and everything else is
/// smaller than it.
struct EmptyHomeView: View {
    @ObservedObject var controller: ParkingController
    @Binding var route: HomeView.Route?

    /// The app's instrument, with nothing in it yet.
    ///
    /// This screen used to lead with a green enamel plate bolted to a pole,
    /// which made a parking sign the largest object on the one screen that has
    /// neither a sign nor a car. The subject here is the car, and the
    /// instrument the app reads it with is the ring that counts a limit down,
    /// so the empty state is that same ring at the same size, unlit. Parking
    /// lights it.
    private var restingDial: some View {
        ZStack {
            Circle()
                .stroke(Kerb.chalkFaint.opacity(0.18), lineWidth: 11)
            Image(systemName: "car.fill")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(Kerb.chalkFaint)
        }
        .frame(width: 196, height: 196)
        .accessibilityHidden(true)
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 40)

                    restingDial.entering(0)

                    Spacer(minLength: 36)

                    VStack(spacing: 10) {
                        Text("Nothing saved")
                            .font(Kerb.voice(.title3))
                            .foregroundStyle(Kerb.chalk)
                        Text(
                            "Save where you left the car, and Kerbside will point you "
                                + "back to it and tell you before your time runs out."
                        )
                        .font(Kerb.voice())
                        .foregroundStyle(Kerb.chalkDim)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                    }
                    .entering(1)

                    Spacer(minLength: 34)

                    VStack(spacing: 16) {
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
                    .entering(2)

                    if controller.location.isDenied {
                        Text(
                            "Location is off for Kerbside, so a spot will remember the "
                                + "time and the sign but not the place."
                        )
                        .kerbCaption(Kerb.chalkFaint, style: .footnote)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 290)
                        .padding(.top, 16)
                    }

                    Spacer(minLength: 24)

                    if !controller.record.past.isEmpty {
                        Button("Past spots") { route = .past }
                            .kerbCaption(Kerb.chalkDim, style: .subheadline, weight: .medium)
                            .entering(3)
                    }

                    Spacer(minLength: 24)
                }
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                .padding(.horizontal, 28)
            }
            .scrollIndicators(.hidden)
        }
    }
}
