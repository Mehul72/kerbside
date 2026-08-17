import SwiftUI

/// What Kerbside is, said once, before it is used.
///
/// This exists because the app shows a countdown next to a parking sign, and
/// that is close enough to advice that it has to be disclaimed in words rather
/// than only in architecture. It says what the app does, what it refuses to
/// do, and that the sign on the street is the authority.
struct FirstRunView: View {
    @Environment(\.dismiss) private var dismiss

    /// Kept in the shared container so a reinstall of the widget extension
    /// cannot resurrect it.
    static let seenKey = "au.kerbside.seenIntroduction"

    static var hasBeenSeen: Bool {
        UserDefaults(suiteName: SharedContainer.appGroup)?.bool(forKey: seenKey)
            ?? UserDefaults.standard.bool(forKey: seenKey)
    }

    /// Whether to show it on this launch.
    ///
    /// The interface tests are about parking, not about being introduced, so
    /// they start past it. One of them asks for it back to check it is there.
    static var shouldShow: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-kerbside-intro") { return true }
        if arguments.contains("-kerbside-reset") { return false }
        return !hasBeenSeen
    }

    static func markSeen() {
        let defaults = UserDefaults(suiteName: SharedContainer.appGroup) ?? .standard
        defaults.set(true, forKey: seenKey)
    }

    var body: some View {
        ZStack {
            Kerb.asphalt.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 28)

                    ZStack {
                        PoleSpine().frame(height: 190)
                        Wordmark()
                    }

                    Text("A notebook, not an authority")
                        .font(Kerb.voice(.title3))
                        .foregroundStyle(Kerb.chalk)
                        .multilineTextAlignment(.center)
                        .padding(.top, 26)

                    VStack(alignment: .leading, spacing: 20) {
                        Point(
                            "It remembers where you parked",
                            "Save the spot, photograph the car, and be pointed back to "
                                + "it with a bearing and a distance."
                        )
                        Point(
                            "It tells you before your time runs out",
                            "Set how long you have and Kerbside counts it down on your "
                                + "Lock Screen, and reminds you before it ends."
                        )
                        Point(
                            "It can read the sign too, if you want",
                            "Photograph a NSW parking plate and it will say what each "
                                + "panel says. It never says whether you may park, and a "
                                + "panel it cannot read stays unread rather than guessed."
                        )
                        Point(
                            "Nothing leaves this device",
                            "No account, no server, no map to fetch. It works in "
                                + "airplane mode."
                        )
                    }
                    .padding(.top, 30)

                    Text(
                        "The sign on the street is the only authority. Read it yourself "
                            + "before you walk away."
                    )
                    .font(Kerb.voice(.footnote))
                    .foregroundStyle(Kerb.amber)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 30)
                    .frame(maxWidth: 320)

                    Button("Start") {
                        FirstRunView.markSeen()
                        dismiss()
                    }
                    .buttonStyle(PlateButton(kind: .enamel))
                    .accessibilityIdentifier("intro-start")
                    .frame(maxWidth: 300)
                    .padding(.top, 32)

                    Spacer(minLength: 30)
                }
                .padding(.horizontal, 28)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
    }

    private struct Point: View {
        let title: String
        let detail: String

        init(_ title: String, _ detail: String) {
            self.title = title
            self.detail = detail
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).kerbLabel(Kerb.chalkDim, style: .caption2)
                Text(detail)
                    .font(Kerb.voice(.subheadline))
                    .foregroundStyle(Kerb.chalk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
