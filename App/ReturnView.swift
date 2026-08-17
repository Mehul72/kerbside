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

    var body: some View {
        ZStack {
            Kerb.asphalt.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 20)

                ZStack {
                    HeroGlow(strength: 0.14)
                    BearingNeedle(
                        bearing: controller.bearing,
                        heading: controller.location.hasCompass ? controller.location.heading : nil
                    )
                }
                .frame(width: 250, height: 250)

                Spacer(minLength: 26)

                readout

                Spacer(minLength: 26)

                footer

                Spacer(minLength: 16)
            }
            .padding(.horizontal, 28)
        }
        .preferredColorScheme(.dark)
        .overlay(alignment: .topTrailing) {
            Button("Done") { dismiss() }
                .kerbLabel(Kerb.chalkDim, style: .footnote)
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
                    .font(.system(size: 52, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Kerb.chalk)
                    .considerate(Kerb.Motion.track, value: Int(metres))

                if let bearing = controller.bearing {
                    Text(Geo.compassPoint(bearing))
                        .kerbLabel(Kerb.amber, style: .subheadline)
                }

                Text("About \(Geo.walkingMinutes(metres: metres)) minutes on foot.")
                    .font(Kerb.voice(.footnote))
                    .foregroundStyle(Kerb.chalkDim)
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
                    .scaledToFill()
                    .frame(height: 110)
                    .clipped()
                    .kerbCard()
                    .accessibilityLabel("Photograph of your parked car")
            }

            if let note = controller.spot?.note, !note.isEmpty {
                Text(note)
                    .font(Kerb.voice(.headline))
                    .foregroundStyle(Kerb.chalk)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .kerbCard(radius: 22)
            }

            if !controller.location.hasCompass, controller.bearing != nil {
                Text("No compass on this device, so the needle points from north rather than from the way you are facing.")
                    .font(Kerb.voice(.footnote))
                    .foregroundStyle(Kerb.chalkFaint)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }

            if let car = controller.spot?.coordinate {
                Button("Walk me there") { openInMaps(car) }
                    .buttonStyle(PlateButton(kind: .outlined))
                    .frame(maxWidth: 300)

                Text("Opens Apple Maps. Kerbside itself never goes online.")
                    .font(Kerb.voice(.caption2))
                    .foregroundStyle(Kerb.chalkFaint)
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

                ForEach(0..<8) { tick in
                    Capsule()
                        .fill(Kerb.chalkFaint.opacity(tick % 2 == 0 ? 0.5 : 0.25))
                        .frame(width: side * 0.012, height: side * (tick % 2 == 0 ? 0.045 : 0.025))
                        .offset(y: -side * 0.44)
                        .rotationEffect(.degrees(Double(tick) * 45))
                }

                if bearing != nil {
                    Needle()
                        .fill(Kerb.amber)
                        .frame(width: side * 0.19, height: side * 0.38)
                        .shadow(color: Kerb.amber.opacity(0.45), radius: side * 0.06)
                        .rotationEffect(.degrees(angle))
                        .considerate(Kerb.Motion.track, value: angle)
                } else {
                    Image(systemName: "location.slash")
                        .font(.system(size: side * 0.22, weight: .light))
                        .foregroundStyle(Kerb.chalkFaint)
                }
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
