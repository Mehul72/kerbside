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

            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 0) {
                        header

                        // Capped, so most of the slack on a tall screen still
                        // falls above the action at the bottom while the dial
                        // gets a little air under the title rather than being
                        // jammed against it.
                        Spacer(minLength: 8).frame(maxHeight: 56)

                        ZStack {
                            HeroGlow(strength: 0.14)
                            BearingNeedle(
                                bearing: controller.bearing,
                                heading: controller.location.hasCompass
                                    ? controller.location.heading
                                    : nil
                            )
                        }
                        .frame(width: 264, height: 264)
                        .padding(.top, 10)

                        readout.padding(.top, 24)

                        context.padding(.top, 24)

                        // The two ends of this screen are fixed to the top and
                        // the bottom and this takes up whatever is left. It
                        // used to be a pair of centring spacers, which stacked
                        // everything into the middle third and left a third of
                        // the screen empty above and below it.
                        Spacer(minLength: 32)

                        timeLeft
                        actions.padding(.top, 14)
                    }
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 20)
                }
                .scrollIndicators(.hidden)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { controller.startTracking() }
        .onDisappear { controller.stopTracking() }
        .onChange(of: controller.location.current?.latitude) { _, _ in
            controller.refreshLiveDistance()
        }
    }

    /// Names the screen rather than leaving a lone Done button floating over
    /// an empty corner.
    private var header: some View {
        HStack {
            Text("Walk back")
                .font(Kerb.voice(.title3))
                .foregroundStyle(Kerb.chalk)
            Spacer()
            Button("Done") { dismiss() }
                .kerbCaption(Kerb.chalkDim, style: .subheadline, weight: .medium)
                .accessibilityIdentifier("done")
        }
        .padding(.top, 6)
    }

    private var readout: some View {
        VStack(spacing: 8) {
            if let metres = controller.metresAway {
                Text(Geo.describe(metres: metres))
                    .font(.system(size: 52 * distanceScale, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Kerb.chalk)
                    .considerate(Kerb.Motion.track, value: Int(metres))

                if let bearing = controller.bearing {
                    // This screen's one loud reading.
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

    /// What the last twenty metres need, which a bearing cannot give: a
    /// picture of the car and whatever was written down about the spot.
    private var context: some View {
        VStack(spacing: 12) {
            if let photo = controller.photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 190)
                    .kerbCard(.primary)
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
        }
    }

    /// How long is left, on the screen you are looking at while walking back.
    ///
    /// The two questions this app answers are how far and how long, and the
    /// walk back only ever answered the first. Somebody is on this screen
    /// precisely because the second one is pressing, and the space was empty
    /// anyway. Quiet, because the needle is the hero here — and named, because
    /// a countdown in this app always says where its number came from.
    @ViewBuilder
    private var timeLeft: some View {
        if let limit = controller.spot?.limit, limit.expiry != nil {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let reading = CountdownReading(limit: limit, now: context.date)

                HStack(spacing: 12) {
                    CountdownFigure(expiry: reading.expiry, now: context.date, size: 22)
                    Text(reading.overrun ? "over" : "left")
                        .kerbCaption(
                            reading.overrun ? Kerb.overdue : Kerb.chalkDim,
                            style: .footnote,
                            weight: .medium
                        )
                    Spacer(minLength: 8)
                    Text(
                        ParkWording.attribution(
                            limit,
                            at: context.date,
                            in: SharedContainer.timeZone
                        )
                    )
                    .kerbCaption(Kerb.chalkFaint, style: .caption2)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 180)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .kerbCard(.quiet)
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        if let car = controller.spot?.coordinate {
            VStack(spacing: 10) {
                Button("Walk me there") { openInMaps(car) }
                    .buttonStyle(PlateButton(kind: .outlined))
                    .frame(maxWidth: 320)

                Text("Opens Apple Maps. Kerbside itself never goes online.")
                    .kerbCaption(Kerb.chalkFaint, style: .caption2)
                    .multilineTextAlignment(.center)
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

    /// Drops the dial's markings and keeps only the needle.
    ///
    /// The same instrument was being drawn at forty points inside a row, where
    /// eight tick marks and a lettered north are smaller than they are legible
    /// and add up to a smudge. At that size the only thing worth reading is
    /// which way the arrow points.
    var compact: Bool = false

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
                    .stroke(Kerb.chalkFaint.opacity(compact ? 0.3 : 0.22), lineWidth: 1)

                if !compact {
                    ForEach(1..<8) { tick in
                        Capsule()
                            .fill(Kerb.chalkFaint.opacity(tick % 2 == 0 ? 0.5 : 0.25))
                            .frame(width: side * 0.012, height: side * (tick % 2 == 0 ? 0.045 : 0.025))
                            .offset(y: -side * 0.44)
                            .rotationEffect(.degrees(Double(tick) * 45))
                    }
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
                if !compact {
                    Text("N")
                        .font(.system(size: side * 0.08, weight: .semibold))
                        .foregroundStyle(Kerb.chalkDim)
                        .offset(y: -side * 0.44)
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
