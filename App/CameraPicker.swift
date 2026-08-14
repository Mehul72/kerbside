import SwiftUI
import UIKit

/// SwiftUI bridge to the system still-camera interface. The captured image is
/// handed directly to the reader and is never saved or uploaded.
struct CameraPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var onCapture: (UIImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented, onCapture: onCapture)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.cameraDevice = .rear
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private var isPresented: Binding<Bool>
        private let onCapture: (UIImage) -> Void

        init(isPresented: Binding<Bool>, onCapture: @escaping (UIImage) -> Void) {
            self.isPresented = isPresented
            self.onCapture = onCapture
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            isPresented.wrappedValue = false
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            }
            isPresented.wrappedValue = false
        }
    }
}
