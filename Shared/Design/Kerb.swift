import SignKit
import SwiftUI

/// The visual language, in one place.
///
/// Kerbside takes its palette and its lettering from the objects it reads. An
/// NSW parking plate is vitreous enamel with a coloured border: green where
/// parking is permitted under conditions, red where stopping is forbidden.
/// Those two colours keep exactly the meaning they have on the street and are
/// never borrowed for anything else — there is no green tick and no red alert
/// anywhere in this interface, because the app does not give verdicts.
enum Kerb {

    // MARK: - Ground

    /// Night asphalt. The ground is dark so a plate reads as a lit object
    /// rather than as a row in a table.
    ///
    /// Cast cool on purpose. A neutral grey ground gives amber nothing to be
    /// warm against, and the whole interface goes flat and slightly grim; a
    /// blue-black makes the same amber read as a light source.
    static let asphalt = Color(red: 0.039, green: 0.047, blue: 0.063)
    static let asphaltRaised = Color(red: 0.075, green: 0.090, blue: 0.122)

    /// What a raised surface is tinted with. Cool, so cards sit in the same
    /// light as the ground rather than looking like grey paper laid on it.
    static let slate = Color(red: 0.443, green: 0.510, blue: 0.616)

    // MARK: - The plate

    /// Enamel white, which is warm rather than pure.
    static let plate = Color(red: 0.957, green: 0.953, blue: 0.933)

    /// The two colours a plate is allowed to be.
    static let signGreen = Color(red: 0.000, green: 0.478, blue: 0.239)
    static let signRed = Color(red: 0.784, green: 0.063, blue: 0.180)

    /// Galvanised steel, for the pole the plates are bolted to.
    static let pole = Color(red: 0.353, green: 0.376, blue: 0.408)

    // MARK: - Interface

    static let chalk = Color(red: 0.933, green: 0.937, blue: 0.945)
    static let chalkDim = Color(red: 0.588, green: 0.620, blue: 0.667)
    static let chalkFaint = Color(red: 0.365, green: 0.396, blue: 0.443)

    /// The only accent, and it marks a reading Kerbside took: a limit counting
    /// down, a bearing to the car, the compass point that bearing lands on.
    /// Amber is the third signal colour, so it stays inside the vocabulary of
    /// the street without colliding with the two that carry meaning on a
    /// plate — and because it means "this is a measurement", it is never spent
    /// on an ordinary control or an optional extra.
    static let amber = Color(red: 0.918, green: 0.647, blue: 0.098)

    /// The same amber, hotter and cooler, for the length of the countdown arc.
    /// A single flat stroke reads as a progress bar bent into a circle; a
    /// filament that brightens towards its head reads as something burning
    /// down, which is what it is.
    static let amberHot = Color(red: 0.996, green: 0.815, blue: 0.365)
    static let amberDeep = Color(red: 0.741, green: 0.451, blue: 0.043)

    /// Past the limit. Deliberately not `signRed`: a plate's red is a
    /// prohibition the street is making, and this is only the clock reporting
    /// that a limit somebody set has been passed. Keeping the two hues apart
    /// stops a countdown from looking like a sign.
    static let overdue = Color(red: 0.937, green: 0.325, blue: 0.314)
    static let overdueHot = Color(red: 1.000, green: 0.510, blue: 0.478)

    // MARK: - Metrics

    static let plateCorner: CGFloat = 12
    static let plateBorderWidth: CGFloat = 3.5
    static let plateInset: CGFloat = 7
    static let plateWidth: CGFloat = 272
    static let plateGap: CGFloat = 18
    static let spineWidth: CGFloat = 5
}

// MARK: - Lettering

extension Kerb {

    /// The sign's own voice. NSW plates are lettered in a condensed heavy
    /// grotesque, and this face is reserved for words that were actually on
    /// the sign — never for Kerbside's description of them.
    static func plateFace(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black).width(.condensed)
    }

    /// Kerbside's voice: what the app understood a panel to say. A serif
    /// against the plates' grotesque, so a reading can never be mistaken for
    /// more sign.
    static func voice(_ style: Font.TextStyle = .body) -> Font {
        .system(style, design: .serif, weight: .regular)
    }

    /// The one loud thing on a screen.
    ///
    /// Expanded, tracked and uppercased is a lot of emphasis for a few words.
    /// Section headers used to take it, all of them at once, which is the same
    /// as none of them taking it. It now marks a single reading per screen —
    /// the word under the countdown, the compass point under the needle — and
    /// headers are set with `kerbSection` instead.
    static func label(_ style: Font.TextStyle = .caption) -> Font {
        .system(style, design: .default, weight: .semibold).width(.expanded)
    }

    /// Small interface text: captions under a control, secondary lines in a
    /// row, the names of things inside a card.
    ///
    /// Sans rather than `voice`. The serif is handsome at twenty points and
    /// mushy at ten on a dark ground, and it should be kept for sentences the
    /// app is actually saying.
    static func ui(_ style: Font.TextStyle = .footnote, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .default, weight: weight)
    }

    /// Machine output that was not understood. Monospace marks it as raw, so
    /// an unread line is never dressed in the lettering of a read one.
    static func data(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .regular, design: .monospaced)
    }
}

// MARK: - Plate tone

/// What colour a plate is painted, taken from what its panel restricts.
///
/// A panel that was not read has no tone to claim, so it is painted in the
/// grey of the pole rather than being guessed into red or green.
enum PlateTone {
    case permissive
    case prohibitive
    case unread

    init(_ restriction: Restriction) {
        switch restriction {
        case .timeLimited:
            self = .permissive
        case .noParking, .noStopping:
            self = .prohibitive
        }
    }

    var ink: Color {
        switch self {
        case .permissive: Kerb.signGreen
        case .prohibitive: Kerb.signRed
        case .unread: Kerb.chalkFaint
        }
    }
}

// MARK: - Shared modifiers

extension View {
    /// The one loud thing on a screen. Rare, and enforced by being spent:
    /// once a screen has used it, nothing else on that screen may.
    func kerbLabel(
        _ colour: Color = Kerb.chalkDim,
        style: Font.TextStyle = .caption
    ) -> some View {
        font(Kerb.label(style))
            .tracking(1.7)
            .textCase(.uppercase)
            .foregroundStyle(colour)
    }

    /// A section header: the name of a part of the screen.
    ///
    /// Set plainly, because there are several of these on a screen and they
    /// are signposts rather than statements. `kerbLabel` used to do this job,
    /// and spending its expanded uppercase on every header meant a screen
    /// shouted four times over and therefore ranked nothing. The loud face is
    /// now kept for the one thing on a screen that has earned it.
    func kerbSection(
        _ colour: Color = Kerb.chalkDim,
        style: Font.TextStyle = .subheadline
    ) -> some View {
        font(Kerb.ui(style, weight: .semibold)).foregroundStyle(colour)
    }

    /// Quiet interface text. The default for anything that is not a header and
    /// not a sentence.
    func kerbCaption(
        _ colour: Color = Kerb.chalkDim,
        style: Font.TextStyle = .footnote,
        weight: Font.Weight = .regular
    ) -> some View {
        font(Kerb.ui(style, weight: weight)).foregroundStyle(colour)
    }
}
