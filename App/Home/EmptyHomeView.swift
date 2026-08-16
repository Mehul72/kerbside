import SwiftUI

/// Home with no car saved.
///
/// One thing to do, said once. Saving a spot is deliberately possible without
/// reading a sign first, because the moment a person needs this app most is
/// the moment they are late and walking away from the car.
struct EmptyHomeView: View {
    @ObservedObject var controller: ParkingController
    @Binding var route: HomeView.Route?

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 20)

                    ZStack {
                        PoleSpine().frame(height: 240)
                        Wordmark()
                    }
                    .entering(0)

                    Spacer(minLength: 30)

                    VStack(spacing: 10) {
                        Text("Nothing saved")
                            .font(Kerb.voice(.title3))
                            .foregroundStyle(Kerb.chalk)
                        Text(
                            "Save where you left the car and Kerbside will point you "
                                + "back to it. Read the sign as well and it will say what "
                                + "the sign says."
                        )
                        .font(Kerb.voice())
                        .foregroundStyle(Kerb.chalkDim)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                    }
                    .entering(1)

                    Spacer(minLength: 34)

                    VStack(spacing: 12) {
                        Button(action: { Task { await controller.park() } }) {
                            Text(controller.isSaving ? "Saving" : "Park here")
                        }
                        .buttonStyle(PlateButton(kind: .enamel))
                        .accessibilityIdentifier("park")
                        .disabled(controller.isSaving)

                        Button("Read the sign first") { route = .reader }
                            .buttonStyle(PlateButton(kind: .outlined))
                            .accessibilityIdentifier("read-sign")
                    }
                    .frame(maxWidth: 300)
                    .entering(2)

                    if controller.location.isDenied {
                        Text(
                            "Location is off for Kerbside, so a spot will remember the "
                                + "time and the sign but not the place."
                        )
                        .font(Kerb.voice(.footnote))
                        .foregroundStyle(Kerb.chalkFaint)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 290)
                        .padding(.top, 16)
                    }

                    Spacer(minLength: 24)

                    if !controller.record.past.isEmpty {
                        Button("Past spots") { route = .past }
                            .font(Kerb.label(.footnote))
                            .tracking(1.4)
                            .textCase(.uppercase)
                            .foregroundStyle(Kerb.chalkDim)
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
