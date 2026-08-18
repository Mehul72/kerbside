import CoreLocation
import MapKit
import ParkKit
import SwiftUI

/// The walk back.
///
/// A needle and a distance, and no map. Map tiles would have to be fetched,
/// and Kerbside works in airplane mode because everything it knows it worked
/// out on the device. Anyone who wants a map can be handed to Apple Maps,
/// which is an app switch rather than a request Kerbside makes.
struct ReturnView: View {
    @ObservedObject var controller: ParkingController
    @Environment(\.dismiss) private var dismiss

    /// The hero number was the last fixed point size on this screen.
    @ScaledMetric(relativeTo: .largeTitle) private var distanceScale: CGFloat = 1

    var body: some View {
        ZStack {
            Kerb.asphalt.ignoresSafeArea()

            VStack(spacing: 22) {
                Spacer(minLength: 8)

                ZStack {
                    HeroGlow(strength: 0.14)
                    BearingNeedle(
                        bearing: controller.bearing,
                        heading: controller.location.hasCompass ? controller.location.heading : nil
                    )
                }
                .frame(width: 232, height: 232)

                readout
                footer

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 28)
        }
        .preferredColorScheme(.dark)
        .overlay(alignment: .topTrailing) {
            Button("Done") { dismiss() }
                .kerbCaption(Kerb.chalkDim, style: .subheadline, weight: .medium)
                .accessibilityIdentifier("done")
                .padding(22)
        }
        .onAppear { controller.startTracking() }
        .onDisappear { controller.stopTracking() }
        .onChange(of: controller.location.current?.latitude) { _, _ in
            controller.refreshLiveDistance()
        }
    }

    private var readout: some View {
        VStack(spacing: 8) {
            if let metres = controller.metresAway {
                Text(Geo.describe(metres: metres))
                    .font(.system(size: 48 * distanceScale, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Kerb.chalk)
                    .considerate(Kerb.Motion.track, value: Int(metres))

                if let bearing = controller.bearing {
                    Text(Geo.compassPoint(bearing))
                        .kerbLabel(Kerb.amber, style: .subheadline)
                }

                Text("About \(Geo.walkingMinutes(metres: metres)) minutes on foot.")
                    .kerbCaption(style: .footnote)
            } else {
                Text("Finding you")
                    .font(Kerb.voice(.title3))
                    .foregroundStyle(Kerb.chalk)
                Text(
                    controller.location.isDenied
                        ? "Location is off for Kerbside, so it cannot work out how far away you are."
                        : "Waiting for a fix from this device."
                )
                .font(Kerb.voice(.footnote))
                .foregroundStyle(Kerb.chalkDim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            // The last twenty metres are the hard part, and a photograph does
            // more for them than any bearing can.
            if let photo = controller.photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 190)
                    .kerbCard()
                    .accessibilityLabel("Photograph of your parked car")
            }

            if let note = controller.spot?.note, !note.isEmpty {
                Text(note)
                    .kerbCaption(Kerb.chalk, style: .subheadline, weight: .medium)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .kerbCard(.quiet, radius: 20)
            }

            if !controller.location.hasCompass, controller.bearing != nil {
                Text("Measured from north, not from the way you are facing.")
                    .kerbCaption(Kerb.chalkFaint, style: .caption)
                    .multilineTextAlignment(.center)
            }

            if let car = controller.spot?.coordinate {
                Button("Walk me there") { openInMaps(car) }
                    .buttonStyle(PlateButton(kind: .outlined))
                    .frame(maxWidth: 300)

                Text("Opens Apple Maps. Kerbside itself never goes online.")
                    .kerbCaption(Kerb.chalkFaint, style: .caption2)
            }
        }
    }

    private func openInMaps(_ car: Coordinate) {
        let placemark = MKPlacemark(
            coordinate: CLLocationCoordinate2D(latitude: car.latitude, longitude: car.longitude)
        )
        let item = MKMapItem(placemark: placemark)
        item.name = "Your car"
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
}

/// The arrow that points at the car.
///
/// When the device has a compass the needle is turned by the bearing less the
/// heading, so it points where the car really is as the phone is turned. With
/// no compass — a simulator, or a device with none — it falls back to pointing
/// from north, and the caller says so rather than letting a wrong arrow look
/// right.
struct BearingNeedle: View {
    /// Degrees clockwise from true north, from here to the car.
    let bearing: Double?
    /// Which way the top of the device is facing, or nil when unknown.
    let heading: Double?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var angle: Double {
        guard let bearing else { return 0 }
        return bearing - (heading ?? 0)
    }

    /// Drawn against whatever frame it is given, so the same needle works at
    /// forty points in a row and at two hundred and fifty on its own screen.
    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)

            ZStack {
                Circle()
                    .stroke(Kerb.chalkFaint.opacity(0.22), lineWidth: 1)

                ForEach(1..<8) { tick in
                    Capsule()
                        .fill(Kerb.chalkFaint.opacity(tick % 2 == 0 ? 0.5 : 0.25))
                        .frame(width: side * 0.012, height: side * (tick % 2 == 0 ? 0.045 : 0.025))
                        .offset(y: -side * 0.44)
                        .rotationEffect(.degrees(Double(tick) * 45))
                }

                if bearing != nil {
                    // The needle lives at the top of a box the size of the
                    // dial, so rotating the box swings it around the hub. A
                    // needle rotated about its own centre floats in the middle
                    // and never reads as being mounted on anything.
                    ZStack(alignment: .top) {
                        Color.clear
                        Needle()
                            .fill(
                                LinearGradient(
                                    colors: [Kerb.amberHot, Kerb.amber],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: side * 0.155, height: side * 0.37)
                            .shadow(color: Kerb.amber.opacity(0.5), radius: side * 0.045)
                            // Stops short of the rim, so it never covers a
                            // dial marking.
                            .padding(.top, side * 0.115)
                    }
                    .frame(width: side, height: side)
                    .rotationEffect(.degrees(angle))
                    .considerate(Kerb.Motion.track, value: angle)

                    // The hub the needle turns on.
                    Circle()
                        .fill(Kerb.asphaltRaised)
                        .frame(width: side * 0.075, height: side * 0.075)
                        .overlay(Circle().strokeBorder(Kerb.amber.opacity(0.55), lineWidth: 1))
                } else {
                    Image(systemName: "location.slash")
                        .font(.system(size: side * 0.22, weight: .light))
                        .foregroundStyle(Kerb.chalkFaint)
                }

                // North, named, and drawn over everything. A dial with an N on
                // it explains the whole of the no-compass case in one glyph,
                // where a paragraph was doing that job before.
                Text("N")
                    .font(.system(size: side * 0.08, weight: .semibold))
                    .foregroundStyle(Kerb.chalkDim)
                    .offset(y: -side * 0.44)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            bearing.map { "The car is \(Geo.compassPoint($0)) of here" } ?? "Direction unknown"
        )
    }
}

/// The same head and shaft as the arrow painted on a plate, stood upright.
/// Kerbside points the way with the sign's own arrow rather than a borrowed
/// glyph.
private struct Needle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let headHeight = rect.height * 0.46
        let shaftWidth = rect.width * 0.26

        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + headHeight))
        path.addLine(to: CGPoint(x: rect.midX + shaftWidth / 2, y: rect.minY + headHeight))
        path.addLine(to: CGPoint(x: rect.midX + shaftWidth / 2, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX - shaftWidth / 2, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX - shaftWidth / 2, y: rect.minY + headHeight))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + headHeight))
        path.closeSubpath()
        return path
    }
}
