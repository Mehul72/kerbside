import SwiftUI
import UIKit

/// The photograph the reading came from, held behind the plates.
///
/// Keeping the picture on screen is what lets a panel be traced back to the
/// part of the sign it was read from. When there is no photograph yet, the
/// ground is plain asphalt.
struct Backdrop: View {
    let image: UIImage?
    var blur: CGFloat
    var dim: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Kerb.asphalt
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .blur(radius: blur, opaque: true)
                        .clipped()
                        .overlay(Color.black.opacity(dim))
                } else {
                    RadialGradient(
                        colors: [Kerb.asphaltRaised, Kerb.asphalt],
                        center: .top,
                        startRadius: 0,
                        endRadius: geometry.size.height
                    )
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Where a normalised Vision box lands on screen, given that the photograph
/// behind it is displayed filled and centre-cropped.
///
/// Vision measures from the bottom left and SwiftUI from the top left, so the
/// vertical axis is flipped here rather than at every call site.
func placement(
    of box: CGRect,
    imageSize: CGSize,
    in container: CGSize
) -> CGRect? {
    guard imageSize.width > 0, imageSize.height > 0,
          container.width > 0, container.height > 0
    else { return nil }

    let scale = max(
        container.width / imageSize.width,
        container.height / imageSize.height
    )
    let displayed = CGSize(
        width: imageSize.width * scale,
        height: imageSize.height * scale
    )
    let origin = CGPoint(
        x: (container.width - displayed.width) / 2,
        y: (container.height - displayed.height) / 2
    )

    return CGRect(
        x: origin.x + box.minX * displayed.width,
        y: origin.y + (1 - box.maxY) * displayed.height,
        width: box.width * displayed.width,
        height: box.height * displayed.height
    )
}

/// The app's name, set as the object it reads.
///
/// Kerbside is a sign reader, so its wordmark is a plate. It is green because
/// green plates are the ones that permit something, and this one permits you
/// to start.
struct Wordmark: View {
    var body: some View {
        Plate(tone: .permissive, lit: false) {
            VStack(spacing: 6) {
                Text("Kerbside")
                    .font(Kerb.plateFace(38))
                    .tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(Kerb.signGreen)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                Text("NSW")
                    .font(.system(size: 12, weight: .semibold).width(.expanded))
                    .tracking(4)
                    .foregroundStyle(Kerb.signGreen.opacity(0.75))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Kerbside")
    }
}

/// The galvanised pole the plates are bolted to, drawn behind the stack so it
/// shows through the gaps between them.
struct PoleSpine: View {
    var body: some View {
        LinearGradient(
            colors: [
                Kerb.pole.opacity(0.35),
                Kerb.pole,
                Kerb.pole.opacity(0.55),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: Kerb.spineWidth)
        .accessibilityHidden(true)
    }
}
