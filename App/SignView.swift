import PhotosUI
import SignKit
import SwiftUI
import UIKit

struct SignView: View {
    /// Set when the reader was opened to put a sign against a parked car. The
    /// reading is offered back rather than kept here, so the record is only
    /// ever written in one place.
    var onUse: ((Sign, UIImage?) -> Void)?
    var onCancel: (() -> Void)?

    @StateObject private var model = SignViewModel()
    @State private var isCameraPresented = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isSelectingSign = false

    private let timeZone = SharedContainer.timeZone

    private var cameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    var body: some View {
        ZStack {
            Kerb.asphalt.ignoresSafeArea()
            content
        }
        .preferredColorScheme(.dark)
        .overlay(alignment: .topLeading) {
            if let onCancel {
                Button("Close", action: onCancel)
                    .font(Kerb.label(.footnote))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(Kerb.chalkDim)
                    .padding(.horizontal, 22)
                    .padding(.top, 8)
            }
        }
        .sheet(isPresented: $isSelectingSign) {
            if let image = model.lastImage {
                SignCropView(
                    image: image,
                    onCancel: { isSelectingSign = false },
                    onSelect: { area in
                        isSelectingSign = false
                        model.readSelection(area)
                    }
                )
            }
        }
        .fullScreenCover(isPresented: $isCameraPresented) {
            CameraPicker(isPresented: $isCameraPresented) { image in
                model.read(image)
            }
            .ignoresSafeArea()
        }
        .onChange(of: selectedPhoto) { item in
            guard let item else { return }
            selectedPhoto = nil
            model.read(item)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .ready:
            CaptureView(
                selectedPhoto: $selectedPhoto,
                cameraAvailable: cameraAvailable,
                openCamera: { isCameraPresented = true }
            )

        case .loadingPhoto:
            ReadingView(
                title: "Loading photo",
                detail: "The photograph you chose stays on this device.",
                photo: nil,
                cancel: model.reset
            )

        case .reading:
            ReadingView(
                title: "Reading sign",
                detail: "Finding the panels on the pole. Nothing is sent anywhere.",
                photo: model.lastImage,
                cancel: model.reset
            )

        case .result(let evaluation):
            PoleResultView(
                evaluation: evaluation,
                plates: model.plates,
                photo: model.lastImage,
                timeZone: timeZone
            )
            .safeAreaInset(edge: .bottom, spacing: 0) { resultActions }

        case .failed(let message):
            NotReadView(
                message: message,
                selectedPhoto: $selectedPhoto,
                cameraAvailable: cameraAvailable,
                openCamera: { isCameraPresented = true },
                photo: model.lastImage,
                selectSign: model.lastImage == nil ? nil : { isSelectingSign = true }
            )
        }
    }

    /// Kept to a single row so the pole stays the screen, with one full-width
    /// action above it when the reading is wanted for a car.
    private var resultActions: some View {
        VStack(spacing: 12) {
            if let onUse, let sign = model.currentSign {
                Button("Use this sign") { onUse(sign, model.lastImage) }
                    .buttonStyle(PlateButton(kind: .enamel))
                    .frame(maxWidth: 340)
            }

            HStack(spacing: 10) {
                CompactAction(
                    title: "Photo",
                    icon: "camera",
                    action: { isCameraPresented = true }
                )
                .disabled(!cameraAvailable)
                .opacity(cameraAvailable ? 1 : 0.4)

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    CompactActionLabel(title: "Library", icon: "photo.on.rectangle")
                }

                if model.lastImage != nil {
                    CompactAction(
                        title: "Select",
                        icon: "crop",
                        action: { isSelectingSign = true }
                    )
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 26)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [.clear, Kerb.asphalt.opacity(0.9), Kerb.asphalt],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }
}

private struct CompactAction: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CompactActionLabel(title: title, icon: icon)
        }
        .buttonStyle(.plain)
    }
}

private struct CompactActionLabel: View {
    let title: String
    let icon: String

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
            Text(title)
                .kerbLabel(Kerb.chalkDim, style: .caption2)
        }
        .foregroundStyle(Kerb.chalk)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background(Color.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Kerb.chalkFaint.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
