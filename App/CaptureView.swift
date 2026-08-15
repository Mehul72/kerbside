import PhotosUI
import SwiftUI
import UIKit

/// The opening screen.
///
/// The hero is the wordmark, set as the object the app reads. Everything else
/// is one instruction and two ways to start.
struct CaptureView: View {
    @Binding var selectedPhoto: PhotosPickerItem?
    let cameraAvailable: Bool
    let openCamera: () -> Void

    @State private var settled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Backdrop(image: nil, blur: 0, dim: 0)

            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: 24)

                        ZStack {
                            PoleSpine()
                                .frame(height: 260)
                            Wordmark()
                        }
                        .offset(y: settled || reduceMotion ? 0 : 18)
                        .opacity(settled || reduceMotion ? 1 : 0)

                        Spacer(minLength: 28)

                        VStack(spacing: 10) {
                            Text("Read the whole pole")
                                .font(Kerb.voice(.title3))
                                .foregroundStyle(Kerb.chalk)
                            Text("Frame every panel from top to bottom. Nothing leaves this device.")
                                .font(Kerb.voice())
                                .foregroundStyle(Kerb.chalkDim)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 290)
                        }
                        .opacity(settled || reduceMotion ? 1 : 0)

                        Spacer(minLength: 32)

                        ActionBar(
                            selectedPhoto: $selectedPhoto,
                            cameraAvailable: cameraAvailable,
                            openCamera: openCamera
                        )

                        if !cameraAvailable {
                            Text("No camera here. Choose an existing photo instead.")
                                .font(Kerb.voice(.footnote))
                                .foregroundStyle(Kerb.chalkFaint)
                                .multilineTextAlignment(.center)
                                .padding(.top, 14)
                                .frame(maxWidth: 290)
                        }

                        Spacer(minLength: 28)
                    }
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                    .padding(.horizontal, 28)
                }
                .scrollIndicators(.hidden)
            }
        }
        .animation(
            reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.8),
            value: settled
        )
        .onAppear { settled = true }
    }
}

/// What to do when the photograph produced nothing to read.
///
/// The failure wears the same outlined plate that an unread panel does, so the
/// interface says "not read" in one consistent way whether that happened to
/// one panel or to the whole picture.
struct NotReadView: View {
    let message: String
    @Binding var selectedPhoto: PhotosPickerItem?
    let cameraAvailable: Bool
    let openCamera: () -> Void
    let photo: UIImage?
    /// Nil when there is no photograph to draw a selection on, so the offer is
    /// only made when it can be taken up.
    let selectSign: (() -> Void)?

    var body: some View {
        ZStack {
            Backdrop(image: photo, blur: 26, dim: 0.84)

            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 40)

                    Plate(tone: .unread, lit: false, dashed: true) {
                        Text("Not read")
                            .kerbLabel(Kerb.chalkFaint)
                            .padding(.vertical, 12)
                    }

                    Text(message)
                        .font(Kerb.voice())
                        .foregroundStyle(Kerb.chalk)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                        .padding(.top, 22)

                    if let selectSign {
                        VStack(spacing: 8) {
                            Button("Select the sign myself", action: selectSign)
                                .buttonStyle(PlateButton(kind: .outlined))
                            Text("Use this when trees, sky or buildings crowd the sign.")
                                .font(Kerb.voice(.footnote))
                                .foregroundStyle(Kerb.chalkFaint)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 280)
                        }
                        .padding(.top, 26)
                    }

                    ActionBar(
                        selectedPhoto: $selectedPhoto,
                        cameraAvailable: cameraAvailable,
                        openCamera: openCamera
                    )
                    .padding(.top, 26)

                    Spacer(minLength: 40)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 28)
            }
        }
    }
}

/// The two ways into a reading, shown identically wherever they appear.
struct ActionBar: View {
    @Binding var selectedPhoto: PhotosPickerItem?
    let cameraAvailable: Bool
    let openCamera: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Button("Take photo", action: openCamera)
                .buttonStyle(PlateButton(kind: .enamel))
                .disabled(!cameraAvailable)
                .opacity(cameraAvailable ? 1 : 0.4)

            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Text("Choose photo")
            }
            .buttonStyle(PlateButton(kind: .outlined))
        }
        .frame(maxWidth: 300)
    }
}

/// Buttons borrow the plate's construction: enamel face with a green rule for
/// the primary action, a plain outline for everything else.
struct PlateButton: ButtonStyle {
    enum Kind {
        case enamel
        case outlined
    }

    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Kerb.label(.subheadline))
            .tracking(1.4)
            .textCase(.uppercase)
            .foregroundStyle(kind == .enamel ? Kerb.signGreen : Kerb.chalk)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(kind == .enamel ? Kerb.plate : Color.white.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        kind == .enamel ? Kerb.signGreen : Kerb.chalkFaint.opacity(0.7),
                        lineWidth: kind == .enamel ? 2.5 : 1
                    )
                    .padding(kind == .enamel ? 4 : 0)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
