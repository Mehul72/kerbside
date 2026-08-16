import ParkKit
import SignKit
import SwiftUI
import UIKit

/// Home with a car saved.
///
/// Top to bottom it answers three questions in the order they are asked: how
/// long does the sign leave me, what does the sign actually say, and where is
/// the car. Every number on this screen names where it came from.
struct ParkedView: View {
    @ObservedObject var controller: ParkingController
    @Binding var route: HomeView.Route?

    @State private var isEditingLimit = false
    @State private var isCollecting = false
    @State private var note = ""
    @State private var reminders: ParkingController.ReminderState = .on
    @FocusState private var noteFocused: Bool

    private let timeZone = SharedContainer.timeZone

    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                header
                countdown
                if let spot = controller.spot, let sign = spot.sign {
                    signSection(spot: spot, sign: sign)
                } else {
                    noSign
                }
                whereSection
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
            let spot = controller.spot
            let reading = spot.map { CountdownReading(limit: $0.limit, now: context.date) }

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

                Text(ParkWording.attribution(spot?.limit ?? .openEnded, in: timeZone))
                    .accessibilityIdentifier("limit-attribution")
                    .font(Kerb.voice(.subheadline))
                    .foregroundStyle(Kerb.chalk)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)

                Button(spot?.limit.expiry == nil ? "Set a limit" : "Change limit") {
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

    // MARK: - The sign

    private func signSection(spot: ParkingSpot, sign: Sign) -> some View {
        VStack(spacing: 24) {
            Divider().overlay(Kerb.chalkFaint.opacity(0.35))

            SignStack(sign: sign, evaluation: controller.evaluation)

            if let evaluation = controller.evaluation {
                RuleNow(evaluation: evaluation, timeZone: timeZone)
            }
        }
        .entering(2)
    }

    private var noSign: some View {
        VStack(spacing: 14) {
            Divider().overlay(Kerb.chalkFaint.opacity(0.35))

            Plate(tone: .unread, lit: false, dashed: true) {
                Text("No sign read")
                    .kerbLabel(Kerb.chalkFaint)
                    .padding(.vertical, 10)
            }
            .accessibilityIdentifier("no-sign")

            Text("Kerbside knows where the car is but not what it is parked under.")
                .font(Kerb.voice(.subheadline))
                .foregroundStyle(Kerb.chalkDim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            Button("Read the sign") { route = .reader }
                .buttonStyle(PlateButton(kind: .outlined))
                .frame(maxWidth: 300)
        }
        .entering(2)
    }

    // MARK: - Where

    /// Waiting for a fix and being refused one are different states, and the
    /// second is the only one somebody can do anything about.
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
        VStack(spacing: 16) {
            Divider().overlay(Kerb.chalkFaint.opacity(0.35))

            Text("Where").kerbLabel(Kerb.chalkDim, style: .caption)
                .frame(maxWidth: .infinity, alignment: .leading)

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
                    .background(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Kerb.chalkFaint.opacity(0.35), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
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
        .entering(4)
    }
}
