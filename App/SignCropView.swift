import SwiftUI
import UIKit

/// Lets a person draw a box around the sign when the surroundings defeat
/// automatic detection.
///
/// Sky, branches and buildings all produce rectangles, and a sign photographed
/// small competes with them. Rather than guess harder, this hands the decision
/// to the one party who can see which shape is the sign.
struct SignCropView: View {
    let image: UIImage
    let onCancel: () -> Void
    /// The chosen area in normalised image coordinates, origin top left.
    let onSelect: (CGRect) -> Void

    @State private var anchor: CGPoint?
    @State private var moving: CGPoint?
    @State private var viewSize: CGSize = .zero

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("Drag a box around one sign.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                GeometryReader { geometry in
                    ZStack(alignment: .topLeading) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: geometry.size.width, height: geometry.size.height)

                        if let box = selection {
                            Rectangle()
                                .strokeBorder(Color.accentColor, lineWidth: 2)
                                .background(Color.accentColor.opacity(0.15))
                                .frame(width: box.width, height: box.height)
                                .offset(x: box.minX, y: box.minY)
                                .allowsHitTesting(false)
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged { value in
                                if anchor == nil { anchor = value.startLocation }
                                moving = value.location
                            }
                    )
                    .onAppear { viewSize = geometry.size }
                    .onChange(of: geometry.size) { newSize in
                        viewSize = newSize
                        anchor = nil
                        moving = nil
                    }
                    .accessibilityLabel("Photograph of the sign")
                    .accessibilityHint("Drag to draw a box around one sign.")
                }

                Text(selection == nil ? "No box drawn yet." : "Ready to read the selection.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("Select the sign")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Read selection") { confirm() }
                        .disabled(selection == nil)
                }
            }
        }
    }

    private var selection: CGRect? {
        guard let anchor, let moving else { return nil }
        let box = CGRect(
            x: min(anchor.x, moving.x),
            y: min(anchor.y, moving.y),
            width: abs(moving.x - anchor.x),
            height: abs(moving.y - anchor.y)
        )
        // A stray tap is not a selection.
        return box.width >= 24 && box.height >= 24 ? box : nil
    }

    /// Where the photograph actually sits inside the view once aspect fitted,
    /// which is what a drawn box has to be measured against.
    private var fittedImageRect: CGRect {
        guard image.size.width > 0, image.size.height > 0,
              viewSize.width > 0, viewSize.height > 0
        else { return .zero }

        let scale = min(viewSize.width / image.size.width, viewSize.height / image.size.height)
        let width = image.size.width * scale
        let height = image.size.height * scale
        return CGRect(
            x: (viewSize.width - width) / 2,
            y: (viewSize.height - height) / 2,
            width: width,
            height: height
        )
    }

    private func confirm() {
        let fitted = fittedImageRect
        guard let box = selection, fitted.width > 0, fitted.height > 0 else { return }

        let clamped = box.intersection(fitted)
        guard !clamped.isNull, clamped.width > 0, clamped.height > 0 else { return }

        onSelect(
            CGRect(
                x: (clamped.minX - fitted.minX) / fitted.width,
                y: (clamped.minY - fitted.minY) / fitted.height,
                width: clamped.width / fitted.width,
                height: clamped.height / fitted.height
            )
        )
    }
}

extension UIImage {
    /// Crops to a normalised rectangle with the origin at the top left.
    ///
    /// The image is redrawn upright first. Cropping the `CGImage` directly
    /// would ignore the orientation flag a camera photograph carries and cut
    /// the wrong region out of it.
    func croppedToNormalised(_ rect: CGRect) -> UIImage? {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let upright = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
        guard let source = upright.cgImage else { return nil }

        let pixels = CGRect(
            x: rect.minX * CGFloat(source.width),
            y: rect.minY * CGFloat(source.height),
            width: rect.width * CGFloat(source.width),
            height: rect.height * CGFloat(source.height)
        ).integral

        guard pixels.width >= 24, pixels.height >= 24,
              let cropped = source.cropping(to: pixels)
        else { return nil }
        return UIImage(cgImage: cropped)
    }
}
