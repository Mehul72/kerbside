import Foundation
import UIKit

/// Photographs of spots, held beside the record in the shared container.
///
/// A picture of where the car actually is answers the question a coordinate
/// cannot: which level, which end, behind which pillar. It is written to disk
/// on this device and nowhere else.
enum PhotoStore {

    /// Small enough that a record's worth of photographs costs nothing, large
    /// enough to recognise a corner of a car park by.
    private static let longestSide: CGFloat = 1200
    private static let quality: CGFloat = 0.72

    static func save(_ image: UIImage, id: UUID) -> String? {
        let filename = "\(id.uuidString).jpg"
        guard let data = shrink(image).jpegData(compressionQuality: quality) else { return nil }
        do {
            try FileManager.default.createDirectory(
                at: SharedContainer.photosDirectory,
                withIntermediateDirectories: true
            )
            try data.write(to: SharedContainer.photoURL(filename), options: .atomic)
            return filename
        } catch {
            return nil
        }
    }

    static func load(_ filename: String) -> UIImage? {
        UIImage(contentsOfFile: SharedContainer.photoURL(filename).path)
    }

    static func remove(_ filename: String) {
        try? FileManager.default.removeItem(at: SharedContainer.photoURL(filename))
    }

    /// Deletes anything no longer referenced, so collecting cars over months
    /// does not quietly fill the device.
    static func prune(keeping filenames: Set<String>) {
        let contents = try? FileManager.default.contentsOfDirectory(
            at: SharedContainer.photosDirectory,
            includingPropertiesForKeys: nil
        )
        for url in contents ?? [] where !filenames.contains(url.lastPathComponent) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func shrink(_ image: UIImage) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > longestSide else { return image }
        let scale = longestSide / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
