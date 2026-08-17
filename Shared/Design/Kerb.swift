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
    static let asphalt = Color(red: 0.055, green: 0.063, blue: 0.071)
    static let asphaltRaised = Color(red: 0.094, green: 0.106, blue: 0.122)

    // MARK: - The plate

    /// Enamel white, which is warm rather than pure.
    static let plate = Color(red: 0.957, green: 0.953, blue: 0.933)

    /// The two colours a plate is allowed to be.
    static let signGreen = Color(red: 0.000, green: 0.478, blue: 0.239)
    static let signRed = Color(red: 0.784, green: 0.063, blue: 0.180)

    /// Galvanised steel, for the pole the plates are bolted to.
    static let pole = Color(red: 0.353, green: 0.376, blue: 0.408)

    // MARK: - Interface

    static let chalk = Color(red: 0.929, green: 0.922, blue: 0.902)
    static let chalkDim = Color(red: 0.588, green: 0.612, blue: 0.639)
    static let chalkFaint = Color(red: 0.365, green: 0.388, blue: 0.416)

    /// The only accent, with one job: marking time. Amber is the third signal
    /// colour, so it stays inside the vocabulary of the street without
    /// colliding with the two that carry meaning on a plate.
    static let amber = Color(red: 0.918, green: 0.647, blue: 0.098)

    /// The same amber, hotter and cooler, for the length of the countdown arc.
    /// A single flat stroke reads as a progress bar bent into a circle; a
    /// filament that brightens towards its head reads as something burning
    /// down, which is what it is.
    static let amberHot = Color(red: 0.996, green: 0.815, blue: 0.365)
    static let amberDeep = Color(red: 0.741, green: 0.451, blue: 0.043)

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

    /// Structure — section labels, time markers, the names of things.
    static func label(_ style: Font.TextStyle = .caption) -> Font {
        .system(style, design: .default, weight: .semibold).width(.expanded)
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
    /// Section labels and time markers share one treatment so that the same
    /// kind of information always looks the same.
    func kerbLabel(
        _ colour: Color = Kerb.chalkDim,
        style: Font.TextStyle = .caption
    ) -> some View {
        font(Kerb.label(style))
            .tracking(1.7)
            .textCase(.uppercase)
            .foregroundStyle(colour)
    }
}
