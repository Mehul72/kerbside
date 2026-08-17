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
                Text("Parked").kerbLabel(Kerb.chalkDim, style: .caption)
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
                Button("Past") { route = .past }
                    .kerbLabel(Kerb.chalkDim, style: .caption)
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
                    CountdownRing(
                        progress: reading?.progress ?? 0,
                        urgent: reading?.urgent ?? false,
                        lineWidth: 11
                    )
                    VStack(spacing: 2) {
                        CountdownFigure(
                            expiry: reading?.expiry,
                            now: context.date,
                            size: 40
                        )
                        .frame(width: 150)
                        Text(caption(for: reading))
                            .kerbLabel(Kerb.chalkDim, style: .caption2)
                    }
                }
                .frame(width: 196, height: 196)

                Text(ParkWording.attribution(controller.spot?.limit ?? .openEnded, in: timeZone))
                    .accessibilityIdentifier("limit-attribution")
                    .font(Kerb.voice(.subheadline))
                    .foregroundStyle(Kerb.chalk)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)

                Button(controller.spot?.limit.expiry == nil ? "Set a limit" : "Change limit") {
                    isEditingLimit = true
                }
                .kerbLabel(Kerb.amber, style: .footnote)
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
                Text("The sign allows").kerbLabel(Kerb.chalkDim, style: .caption)
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
            .background(Kerb.amber.opacity(0.07))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Kerb.amber.opacity(0.35), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            Divider().overlay(Kerb.chalkFaint.opacity(0.35))

            Text("Where the car is").kerbLabel(Kerb.chalkDim, style: .caption)
                .frame(maxWidth: .infinity, alignment: .leading)

            photoCard

            if controller.spot?.coordinate != nil {
                Button { route = .walkBack } label: {
                    HStack(spacing: 14) {
                        BearingNeedle(bearing: controller.bearing, heading: nil)
                            .frame(width: 42, height: 42)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(controller.distance ?? placeholder)
                                .font(Kerb.voice(.headline))
                                .foregroundStyle(Kerb.chalk)
                                .considerate(Kerb.Motion.track, value: controller.distance)
                            Text(detail)
                                .font(Kerb.voice(.footnote))
                                .foregroundStyle(Kerb.chalkDim)
                        }

                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .foregroundStyle(Kerb.chalkFaint)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .background(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Kerb.chalkFaint.opacity(0.35), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
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

            TextField(
                "",
                text: $note,
                prompt: Text("Level 3, bay 12").foregroundStyle(Kerb.chalkFaint)
            )
            .font(Kerb.voice(.subheadline))
            .foregroundStyle(Kerb.chalk)
            .focused($noteFocused)
            .submitLabel(.done)
            .onSubmit { controller.setNote(note) }
            .padding(14)
            .background(Color.white.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        noteFocused ? Kerb.amber.opacity(0.6) : Kerb.chalkFaint.opacity(0.35),
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                    .scaledToFill()
                    .frame(height: 170)
                    .clipped()
                    .overlay(alignment: .bottomLeading) {
                        Text("Your car")
                            .kerbLabel(Kerb.chalk, style: .caption2)
                            .padding(10)
                            .background(.black.opacity(0.45), in: Capsule())
                            .padding(10)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("car-photo")
            .accessibilityLabel("Photograph of your parked car")
        } else if cameraAvailable {
            Button { isTakingPhoto = true } label: { photoInvitation }
                .buttonStyle(.plain)
                .accessibilityIdentifier("take-photo")
        } else {
            // No camera here — a simulator, or a device without one. A picture
            // already in the library answers the same question.
            PhotosPicker(selection: $pickedPhoto, matching: .images) {
                photoInvitation
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("take-photo")
        }
    }

    private var photoInvitation: some View {
        HStack(spacing: 12) {
            Image(systemName: cameraAvailable ? "camera" : "photo.on.rectangle")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Kerb.amber)
            VStack(alignment: .leading, spacing: 2) {
                Text(cameraAvailable ? "Photograph the car" : "Add a photo of the car")
                    .font(Kerb.voice(.headline))
                    .foregroundStyle(Kerb.chalk)
                Text("The quickest way to find it again.")
                    .font(Kerb.voice(.footnote))
                    .foregroundStyle(Kerb.chalkDim)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    Kerb.chalkFaint.opacity(0.35),
                    style: StrokeStyle(lineWidth: 1, dash: [6, 5])
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - The sign, if there is one

    /// Folded away by default. A sign is worth keeping and worth showing, but
    /// it is not what somebody opens this app to look at.
    private var signSection: some View {
        VStack(spacing: 14) {
            Divider().overlay(Kerb.chalkFaint.opacity(0.35))

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
                        Text(summary(of: sign))
                            .font(Kerb.voice(.footnote))
                            .foregroundStyle(Kerb.chalkDim)
                            .lineLimit(1)
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
                        .kerbLabel(Kerb.chalkDim, style: .footnote)
                }
            } else {
                Button("Read the sign · optional") { route = .reader }
                    .kerbLabel(Kerb.chalkDim, style: .footnote)
                    .accessibilityIdentifier("read-sign")
            }
        }
        .entering(4)
    }

    /// The sign in one line, for the folded state.
    private func summary(of sign: Sign) -> String {
        guard let panel = sign.parsedPanels.first else { return "Not read" }
        var text = Wording.describe(panel)
        let others = sign.panels.count - 1
        if others > 0 { text += " · \(others) more" }
        return text
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 12) {
            Button("I'm back at the car") {
                noteFocused = false
                isCollecting = true
            }
            .buttonStyle(PlateButton(kind: .enamel))
            .accessibilityIdentifier("collect")

            switch reminders {
            case .on:
                EmptyView()

            case .off:
                Button("Turn on reminders") {
                    Task {
                        _ = await controller.requestReminders()
                        reminders = await controller.reminderState()
                    }
                }
                .kerbLabel(Kerb.chalkDim, style: .footnote)
                .accessibilityIdentifier("reminders")
                .padding(.top, 4)

            case .refused:
                // iOS will not ask twice, so offering the ask again would be a
                // button that does nothing. Settings is the only way back.
                Button("Reminders are off · open Settings") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
                .kerbLabel(Kerb.chalkDim, style: .footnote)
                .accessibilityIdentifier("reminders-settings")
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: 320)
        .entering(5)
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
