import SwiftUI

/// The promises Kerbside makes, available again after the first launch.
///
/// App Review requires the privacy policy to be easy to reach from inside the
/// app. Keeping support and the safety boundary beside it also means the first
/// run explanation is not the only time someone can find them.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private let privacyURL = URL(string: "https://mehul72.github.io/kerbside/privacy/")!
    private let supportURL = URL(string: "https://mehul72.github.io/kerbside/support/")!

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Wordmark()
                        .frame(maxWidth: 280)

                    VStack(spacing: 8) {
                        Text("A notebook, not an authority")
                            .font(Kerb.voice(.title3))
                            .foregroundStyle(Kerb.chalk)
                            .multilineTextAlignment(.center)

                        Text(
                            "Kerbside remembers where you parked, reads NSW parking "
                                + "plates on this iPhone, and counts down a limit you choose."
                        )
                        .font(Kerb.voice(.subheadline))
                        .foregroundStyle(Kerb.chalkDim)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    Text(
                        "It never decides whether you may park. The sign on the street "
                            + "is the only authority, and a panel Kerbside cannot read "
                            + "stays unread rather than guessed."
                    )
                    .font(Kerb.voice(.footnote))
                    .foregroundStyle(Kerb.amber)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .kerbCard(tint: Kerb.amber)

                    VStack(spacing: 12) {
                        externalLink(
                            "Privacy policy",
                            detail: "What stays on this iPhone",
                            symbol: "hand.raised",
                            destination: privacyURL,
                            identifier: "privacy-policy"
                        )
                        externalLink(
                            "Support",
                            detail: "Contact and help",
                            symbol: "questionmark.circle",
                            destination: supportURL,
                            identifier: "support"
                        )
                    }

                    Text(version)
                        .kerbCaption(Kerb.chalkFaint, style: .caption)
                }
                .padding(.horizontal, 26)
                .padding(.top, 24)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .background(Kerb.asphalt)
            .navigationTitle("About Kerbside NSW")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(version) (\(build))"
    }

    private func externalLink(
        _ title: String,
        detail: String,
        symbol: String,
        destination: URL,
        identifier: String
    ) -> some View {
        Link(destination: destination) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Kerb.amber)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Kerb.ui(.headline, weight: .semibold))
                        .foregroundStyle(Kerb.chalk)
                    Text(detail).kerbCaption(style: .footnote)
                }

                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Kerb.chalkFaint)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .kerbCard(.primary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}
