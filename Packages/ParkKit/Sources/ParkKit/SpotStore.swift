import Foundation

/// The record on disk.
///
/// One JSON file, written by the app and read by the app, the widgets and the
/// Live Activity. The location of the file is injected rather than looked up,
/// so the app can hand over an App Group container while a test hands over a
/// temporary directory and neither needs to know about the other.
public struct SpotStore: Sendable {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// The file's name inside whichever container it is given, so the app and
    /// the widget extension cannot disagree about it.
    public static let filename = "parking.json"

    public static func url(inContainer directory: URL) -> URL {
        directory.appendingPathComponent(filename)
    }

    /// Empty when nothing has been written yet. Throws when something has been
    /// written and cannot be read, because silently starting again from empty
    /// would lose a car.
    public func load() throws -> ParkingRecord {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .empty }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return .empty }
        return try Self.decoder.decode(ParkingRecord.self, from: data)
    }

    /// For the widget timeline, where there is nobody to show an error to and
    /// an empty widget is the honest outcome.
    public func loadOrEmpty() -> ParkingRecord {
        (try? load()) ?? .empty
    }

    public func save(_ record: ParkingRecord) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let data = try Self.encoder.encode(record)
        // Atomic, so a widget reading mid-write sees the old record rather
        // than half of the new one.
        try data.write(to: fileURL, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
