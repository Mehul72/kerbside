import SignKit
import SwiftUI
import UIKit

/// The screen Kerbside opens to.
///
/// There is one question worth answering on launch — where is the car and how
/// long does the sign leave it — so there is one screen that answers it. The
/// camera is an action within that screen rather than a destination of its
/// own, because reading a sign is something you do about a car, not instead of
/// one.
struct HomeView: View {
    @StateObject private var controller = ParkingController()
    @State private var route: Route?
    @State private var isIntroducing = FirstRunView.shouldShow
    @Environment(\.scenePhase) private var scenePhase

    enum Route: Hashable, Identifiable {
        case reader
        case walkBack
        case past
        var id: Self { self }
    }

    var body: some View {
        ZStack {
            Backdrop(image: nil, blur: 0, dim: 0)

            Group {
                if controller.isParked {
                    ParkedView(controller: controller, route: $route)
                } else {
                    EmptyHomeView(controller: controller, route: $route)
                }
            }
            .considerate(Kerb.Motion.arrive, value: controller.isParked)
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $isIntroducing) { FirstRunView() }
        .sheet(item: $route) { destination in
            switch destination {
            case .reader:
                SignView(
                    onUse: { sign, photo in
                        route = nil
                        use(sign: sign, photo: photo)
                    },
                    onCancel: { route = nil }
                )
            case .walkBack:
                ReturnView(controller: controller)
            case .past:
                PastSpotsView(controller: controller)
            }
        }
        .alert(
            "Kerbside",
            isPresented: Binding(
                get: { controller.failure != nil },
                set: { if !$0 { controller.failure = nil } }
            )
        ) {
            Button("OK") { controller.failure = nil }
        } message: {
            Text(controller.failure ?? "")
        }
        .onOpenURL { url in
            // Everything outside the app — a widget, the Lock Screen banner,
            // the Dynamic Island — points here. The walk back is what somebody
            // tapping one of those is almost always after, so long as there is
            // a place to walk to.
            guard url.scheme == "kerbside" else { return }
            controller.reload()
            route = controller.spot?.coordinate == nil ? nil : .walkBack
        }
        .onChange(of: scenePhase) { _, phase in
            // A widget tap or a Live Activity can change nothing, but time
            // passes while the app is away and the sign may now read
            // differently. Re-reading on return costs one file read.
            guard phase == .active else { return }
            controller.reload()
            // Time passed and the car may be further away than it was, so the
            // distance is asked for again rather than left as it was found.
            Task { await controller.refreshHere() }
        }
    }

    /// A sign read from the reader either starts a new record or joins the car
    /// that is already parked.
    private func use(sign: Sign, photo: UIImage?) {
        if controller.isParked {
            controller.attach(sign: sign)
        } else {
            Task { await controller.park(sign: sign) }
        }
    }
}
