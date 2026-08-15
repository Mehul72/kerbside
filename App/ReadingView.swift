import SwiftUI
import UIKit

/// The moment between the photograph and the pole.
///
/// The picture is already on screen, darkening, with a single pass travelling
/// down it. That pass is the only thing standing in for work happening, and it
/// stops when motion is reduced.
struct ReadingView: View {
    let title: String
    let detail: String
    let photo: UIImage?
    let cancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Backdrop(image: photo, blur: 8, dim: 0.72)

            if !reduceMotion {
                ScanPass()
                    .allowsHitTesting(false)
            }

            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: 32)

                        VStack(spacing: 12) {
                            Text(title)
                                .kerbLabel(Kerb.amber)
                            Text(detail)
                                .font(Kerb.voice())
                                .foregroundStyle(Kerb.chalkDim)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 280)
                        }
                        .accessibilityElement(children: .combine)

                        Spacer(minLength: 32)

                        Button("Cancel", action: cancel)
                            .buttonStyle(PlateButton(kind: .outlined))
                            .frame(maxWidth: 300)
                            .padding(.bottom, 36)
                    }
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                    .padding(.horizontal, 28)
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

/// A single amber pass down the photograph.
private struct ScanPass: View {
    var body: some View {
        TimelineView(.animation) { context in
            GeometryReader { geometry in
                let height = geometry.size.height
                let cycle = 2.1
                let progress = context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: cycle) / cycle

                LinearGradient(
                    colors: [.clear, Kerb.amber.opacity(0.5), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: height * 0.22)
                .offset(y: -height * 0.22 + progress * height * 1.22)
                .blendMode(.plusLighter)
            }
        }
    }
}
