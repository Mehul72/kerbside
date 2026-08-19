import ParkKit
import PhotosUI
import SignKit
import SwiftUI
import UIKit

/// Home with a car saved.
///
/// The order answers the questions in the order they are actually asked: how
/// long have I got, where is the car, and only then what was written on the
/// pole. Reading a sign is something you do *about* a parked car, so it sits
/// below the car rather than above it, and it stays folded away until asked
/// for.
struct ParkedView: View {
    @ObservedObject var controller: ParkingController
    @Binding var route: HomeView.Route?

    @State private var isEditingLimit = false
    @State private var isCollecting = false
    @State private var isTakingPhoto = false
    @State private var isShowingPhoto = false
    @State private var isShowingSign = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var note = ""
    @State private var reminders: ParkingController.ReminderState = .on
    @FocusState private var noteFocused: Bool

    private let timeZone = SharedContainer.timeZone

    private var cameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header
                countdown
                suggestion
                whereSection
                signSection
                actions
            }
            .padding(.horizontal, 26)
            .padding(.top, 12)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .sheet(isPresented: $isEditingLimit) {
            LimitSheet(controller: controller)
                .presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: $isTakingPhoto) {
            CameraPicker(isPresented: $isTakingPhoto) { image in
                controller.setPhoto(image)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $isShowingPhoto) {
            if let photo = controller.photo {
                PhotoView(image: photo) { controller.removePhoto() }
            }
        }
        .confirmationDialog(
            "Finished with this spot?",
            isPresented: $isCollecting,
            titleVisibility: .visible
        ) {
            Button("I'm back at the car") { controller.collect() }
                .accessibilityIdentifier("collect-confirm")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The spot moves to your past spots and the countdown stops.")
        }
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            pickedPhoto = nil
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data)
                else { return }
                controller.setPhoto(image)
            }
        }
        .task {
            note = controller.spot?.note ?? ""
            reminders = await controller.reminderState()
            await controller.refreshHere()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Parked").kerbSection()
                if let spot = controller.spot {
                    Text(
                        ParkWording.dayAndClock(
                            spot.parkedAt,
                            relativeTo: controller.instant,
                            in: timeZone
                        )
                    )
                    .font(Kerb.voice(.title3))
                    .foregroundStyle(Kerb.chalk)
                }
            }
            Spacer()
            if !controller.record.past.isEmpty {
                Button {
                    route = .past
                } label: {
                    HStack(spacing: 3) {
                        Text("Past")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .kerbCaption(Kerb.chalkDim, style: .subheadline, weight: .medium)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("past")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .entering(0)
    }

    // MARK: - Countdown

    /// The ring redraws every second while this screen is up. The falling
    /// figure inside it is drawn by the system from an expiry, so it stays
    /// right even when this view is not being refreshed at all.
    private var countdown: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let reading = controller.spot.map {
                CountdownReading(limit: $0.limit, now: context.date)
            }

            VStack(spacing: 16) {
                ZStack {
                    HeroGlow(
                        tint: reading?.overrun == true ? Kerb.overdue : Kerb.amber,
                        strength: reading?.urgent == true || reading?.overrun == true ? 0.26 : 0.16
                    )
                    CountdownRing(
                        progress: reading?.progress ?? 0,
                        urgent: reading?.urgent ?? false,
                        overrun: reading?.overrun ?? false,
                        lineWidth: 13
                    )
                    VStack(spacing: 2) {
                        CountdownFigure(
                            expiry: reading?.expiry,
                            now: context.date,
                            size: 48
                        )
                        Text(caption(for: reading))
                            .kerbLabel(
                                reading?.overrun == true ? Kerb.overdue : Kerb.chalkDim,
                                style: .caption2
                            )
                    }
                }
                // The app has one hero and this is it. At 196 it was merely
                // the largest thing on the screen; at 244 it is what the
                // screen is for, and everything under it can afford to be
                // quieter still.
                .frame(width: 244, height: 244)

                Text(
                    ParkWording.attribution(
                        controller.spot?.limit ?? .openEnded,
                        at: context.date,
                        in: timeZone
                    )
                )
                    .accessibilityIdentifier("limit-attribution")
                    .font(Kerb.voice(.subheadline))
                    .foregroundStyle(Kerb.chalk)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)

                Button(controller.spot?.limit.expiry == nil ? "Set a limit" : "Change limit") {
                    isEditingLimit = true
                }
                .kerbCaption(Kerb.amber, style: .subheadline, weight: .medium)
                .accessibilityIdentifier("edit-limit")
            }
        }
        .entering(1)
    }

    private func caption(for reading: CountdownReading?) -> String {
        guard let reading, reading.expiry != nil else { return "no limit" }
        return reading.overrun ? "over" : "left"
    }

    // MARK: - What the sign allows

    /// The one place a sign earns space near the top: an allowance it states,
    /// offered as a limit, while nothing has been committed yet.
    @ViewBuilder
    private var suggestion: some View {
        if let candidate = controller.suggestion {
            VStack(spacing: 12) {
                Text("The sign allows").kerbSection()
                Text(ParkWording.describe(candidate, in: timeZone))
                    .font(Kerb.voice(.subheadline))
                    .foregroundStyle(Kerb.chalk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Count this down") { controller.choose(candidate) }
                    .buttonStyle(PlateButton(kind: .enamel))
                    .accessibilityIdentifier("use-suggestion")
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .kerbCard(tint: Kerb.amber)
            .entering(2)
        }
    }

    // MARK: - Where the car is

    private var placeholder: String {
        controller.location.isDenied ? "Location is off" : "Finding you"
    }

    private var detail: String {
        if controller.distance != nil { return "Walk me back to the car" }
        return controller.location.isDenied
            ? "Turn location on in Settings to be pointed back."
            : "Waiting for a fix from this device."
    }

    private var whereSection: some View {
        VStack(spacing: 14) {
            Hairline()

            Text("Where the car is").kerbSection()
                .frame(maxWidth: .infinity, alignment: .leading)

            if controller.spot?.coordinate != nil {
                Button { route = .walkBack } label: {
                    HStack(spacing: 14) {
                        BearingNeedle(bearing: controller.bearing, heading: nil, compact: true)
                            .frame(width: 44, height: 44)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(controller.distance ?? placeholder)
                                .font(Kerb.voice(.headline))
                                .foregroundStyle(Kerb.chalk)
                                .considerate(Kerb.Motion.track, value: controller.distance)
                            Text(detail)
                                .kerbCaption(style: .footnote)
                        }

                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .foregroundStyle(Kerb.chalkFaint)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .kerbCard(.primary)
                }
                .kerbPressable()
                .accessibilityIdentifier("walk-back")
            } else {
                Text(
                    "No location was recorded for this spot, so Kerbside cannot point "
                        + "the way back to it."
                )
                .font(Kerb.voice(.subheadline))
                .foregroundStyle(Kerb.chalkDim)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            photoCard

            HStack(spacing: 11) {
                Image(systemName: "pencil.line")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(noteFocused ? Kerb.amber : Kerb.chalkFaint)
                TextField(
                    "",
                    text: $note,
                    prompt: Text("Add a note (level 3, bay 12)")
                        .foregroundStyle(Kerb.chalkFaint)
                )
                .font(Kerb.voice(.subheadline))
                .foregroundStyle(Kerb.chalk)
                .focused($noteFocused)
                .submitLabel(.done)
                .onSubmit { controller.setNote(note) }
            }
            .padding(14)
            .kerbCard(.quiet, tint: noteFocused ? Kerb.amber : nil)
            .considerate(Kerb.Motion.settle, value: noteFocused)
            .onChange(of: noteFocused) { _, focused in
                if !focused { controller.setNote(note) }
            }
        }
        .entering(3)
    }

    /// A photograph of the car, which is the thing that actually finds it in a
    /// car park where every level looks the same.
    @ViewBuilder
    private var photoCard: some View {
        if let photo = controller.photo {
            Button { isShowingPhoto = true } label: {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .kerbCard()
            }
            .kerbPressable()
            .accessibilityIdentifier("car-photo")
            .accessibilityLabel("Photograph of your parked car")
        } else if cameraAvailable {
            Button { isTakingPhoto = true } label: { photoInvitation }
                .kerbPressable()
                .accessibilityIdentifier("take-photo")
        } else {
            // No camera here — a simulator, or a device without one. A picture
            // already in the library answers the same question.
            PhotosPicker(selection: $pickedPhoto, matching: .images) {
                photoInvitation
            }
            .accessibilityIdentifier("take-photo")
        }
    }

    /// An offer, not an instruction.
    ///
    /// This was drawn in amber with the section's brightest text, which made
    /// the optional extra louder than the row that walks you back to the car.
    /// The accent is the app's own reading of something — a time, a bearing —
    /// and an invitation to add a photograph is neither.
    private var photoInvitation: some View {
        HStack(spacing: 12) {
            Image(systemName: cameraAvailable ? "camera" : "photo.on.rectangle")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Kerb.chalkDim)
            VStack(alignment: .leading, spacing: 2) {
                Text(cameraAvailable ? "Photograph the car" : "Add a photo of the car")
                    .kerbCaption(Kerb.chalkDim, style: .subheadline, weight: .medium)
                Text("The quickest way to find it again.")
                    .kerbCaption(Kerb.chalkFaint, style: .footnote)
            }
            Spacer(minLength: 0)
        }
        .padding(15)
        .frame(maxWidth: .infinity)
        .kerbCard(.quiet, dashed: true)
    }

    // MARK: - The sign, if there is one

    /// Folded away by default. A sign is worth keeping and worth showing, but
    /// it is not what somebody opens this app to look at.
    private var signSection: some View {
        VStack(spacing: 14) {
            Hairline()

            if let sign = controller.spot?.sign {
                Button {
                    withAnimation(Kerb.Motion.settle) { isShowingSign.toggle() }
                } label: {
                    HStack(spacing: 12) {
                        if let panel = sign.parsedPanels.first {
                            PlateBadge(
                                text: ParkWording.plateHeadline(panel),
                                tone: PlateTone(panel.restriction),
                                size: 13
                            )
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(hours(of: sign))
                                .kerbCaption(Kerb.chalk, style: .subheadline, weight: .medium)
                            if let extra = others(of: sign) {
                                Text(extra).kerbCaption(style: .caption)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: isShowingSign ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Kerb.chalkFaint)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("toggle-sign")

                if isShowingSign {
                    SignStack(sign: sign, evaluation: controller.evaluation)
                    if let evaluation = controller.evaluation {
                        RuleNow(evaluation: evaluation, timeZone: timeZone)
                    }
                    Button("Read it again") { route = .reader }
                        .kerbCaption(Kerb.chalkDim, style: .subheadline, weight: .medium)
                }
            } else {
                Button {
                    route = .reader
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "viewfinder")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Read the sign")
                            .font(Kerb.ui(.subheadline, weight: .medium))
                    }
                    .foregroundStyle(Kerb.chalkDim)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("read-sign")
            }
        }
        .entering(4)
    }

    /// The governing panel's hours, short enough to fit on one line beside a
    /// badge.
    ///
    /// The whole sentence used to go here and be cut off mid-word — "2 hour
    /// parking, every day, 6am to 11pm · 1…" — which told a reader nothing and
    /// looked like a fault. The badge already carries the allowance, so this
    /// only has to carry when it applies.
    private func hours(of sign: Sign) -> String {
        guard let panel = sign.parsedPanels.first else { return "Not read" }
        let days = Wording.describe(panel.days)
        let times = Wording.describe(panel.times)
        return times == "at all times" ? days.capitalisedFirst : "\(days), \(times)".capitalisedFirst
    }

    /// What else is on the pole, counted rather than spelled out.
    private func others(of sign: Sign) -> String? {
        let rest = sign.panels.count - 1
        guard rest > 0 else { return nil }
        return rest == 1 ? "1 more panel" : "\(rest) more panels"
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 14) {
            remindersNotice

            Button("I'm back at the car") {
                noteFocused = false
                isCollecting = true
            }
            .buttonStyle(PlateButton(kind: .outlined))
            .accessibilityIdentifier("collect")
        }
        .frame(maxWidth: 320)
        .entering(5)
    }

    /// Said plainly, and above the button rather than under it.
    ///
    /// Kerbside's whole promise is that it tells you before your time runs
    /// out, and with reminders off it cannot keep that promise. That was
    /// reported by a single line of link text at the very bottom of a long
    /// scroll — the quietest thing on the screen was the one telling you the
    /// app would not do its job. It states the consequence now, and it is a
    /// notice rather than a shout because nothing has gone wrong yet.
    @ViewBuilder
    private var remindersNotice: some View {
        switch reminders {
        case .on:
            EmptyView()

        case .off:
            notice("Turn on reminders", id: "reminders") {
                Task {
                    _ = await controller.requestReminders()
                    reminders = await controller.reminderState()
                }
            }

        case .refused:
            // iOS will not ask twice, so offering the ask again would be a
            // button that does nothing. Settings is the only way back.
            notice("Open Settings", id: "reminders-settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
        }
    }

    private func notice(
        _ action: String,
        id: String,
        perform: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reminders are off, so Kerbside cannot tell you before the limit runs out.")
                .font(Kerb.voice(.footnote))
                .foregroundStyle(Kerb.chalkDim)
                .fixedSize(horizontal: false, vertical: true)

            // Chalk, not amber: the accent marks a reading Kerbside took or
            // the control that sets one, and turning on notifications is
            // neither.
            Button(action, action: perform)
                .kerbCaption(Kerb.chalk, style: .subheadline, weight: .semibold)
                .accessibilityIdentifier(id)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kerbCard(.quiet)
    }
}

/// The car's photograph, full size, with the one thing you might want to do to
/// it: take it again, or drop it.
private struct PhotoView: View {
    let image: UIImage
    let onRemove: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Kerb.asphalt.ignoresSafeArea()
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            }
            .navigationTitle("Your car")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Remove", role: .destructive) {
                        onRemove()
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}


extension String {
    /// Sentence case, for phrases SignKit hands over in lower case because they
    /// are normally used mid-sentence.
    var capitalisedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
