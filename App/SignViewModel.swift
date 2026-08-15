import Foundation
import ImageIO
import PhotosUI
import SignKit
import SignVision
import SwiftUI
import UIKit

/// One panel as the interface draws it: what was read, and where on the
/// photograph it was read from.
///
/// The provenance is what lets a plate be sent back to the part of the sign it
/// came from, which is the only way to see whether a panel was cut out of the
/// photograph correctly.
struct PlateItem: Identifiable {
    let id: Int
    let result: PanelResult
    /// Normalised, with Vision's bottom-left origin. Nil when the reading
    /// carried no geometry for this panel.
    let sourceBox: CGRect?
}

@MainActor
final class SignViewModel: ObservableObject {
    enum Phase {
        case ready
        case loadingPhoto
        case reading
        case result(Evaluation)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .ready
    /// Every panel in the order it appears on the pole, unknowns included.
    /// The evaluation sorts panels by whether they are in force; this keeps
    /// the order the sign is actually written in, which is what gets drawn.
    @Published private(set) var plates: [PlateItem] = []

    private let recognizer: SignRecognizer
    private let timeZone: TimeZone
    private var sign: Sign?
    /// The photograph the current reading came from, kept so the same picture
    /// can be read again from a hand drawn selection without asking for it a
    /// second time.
    private(set) var lastImage: UIImage?
    private var readingTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var requestID = 0

    init(
        recognizer: SignRecognizer = SignRecognizer(),
        timeZone: TimeZone = TimeZone(identifier: "Australia/Sydney")!
    ) {
        self.recognizer = recognizer
        self.timeZone = timeZone
    }

    func read(_ image: UIImage) {
        let requestID = beginRequest(phase: .reading)
        readingTask = Task { [weak self] in
            guard let self else { return }
            await recognize(image, requestID: requestID)
        }
    }

    func read(_ item: PhotosPickerItem) {
        let requestID = beginRequest(phase: .loadingPhoto)
        readingTask = Task { [weak self] in
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data)
                else {
                    self?.failPhotoLoad(requestID: requestID)
                    return
                }
                guard let self, isCurrent(requestID) else { return }
                phase = .reading
                await recognize(image, requestID: requestID)
            } catch is CancellationError {
                return
            } catch {
                self?.failPhotoLoad(requestID: requestID)
            }
        }
    }

    func reset() {
        requestID &+= 1
        readingTask?.cancel()
        refreshTask?.cancel()
        readingTask = nil
        sign = nil
        plates = []
        lastImage = nil
        phase = .ready
    }

    /// Reads the same photograph again, restricted to an area the person drew.
    /// Used when the surroundings defeat automatic sign detection.
    func readSelection(_ normalised: CGRect) {
        guard let image = lastImage,
              let cropped = image.croppedToNormalised(normalised)
        else {
            fail("That selection was too small to read. Try a larger box.", requestID: requestID)
            return
        }
        read(cropped)
    }

    private func recognize(_ image: UIImage, requestID: Int) async {
        lastImage = image
        guard let cgImage = image.cgImage else {
            fail(
                "The photograph could not be opened. Choose another photo.",
                requestID: requestID
            )
            return
        }

        do {
            let reading = try await recognizer.read(
                cgImage,
                orientation: image.imageOrientation.cgImageOrientation
            )
            guard isCurrent(requestID) else { return }
            sign = reading.sign
            plates = Self.plateItems(from: reading)
            readingTask = nil
            refreshEvaluation()
        } catch is CancellationError {
            return
        } catch {
            fail(
                (error as? LocalizedError)?.errorDescription
                    ?? "The photograph could not be read.",
                requestID: requestID
            )
        }
    }

    private func beginRequest(phase: Phase) -> Int {
        requestID &+= 1
        readingTask?.cancel()
        refreshTask?.cancel()
        readingTask = nil
        sign = nil
        plates = []
        self.phase = phase
        return requestID
    }

    private func isCurrent(_ requestID: Int) -> Bool {
        requestID == self.requestID && !Task.isCancelled
    }

    private func failPhotoLoad(requestID: Int) {
        fail(
            "The selected photo could not be opened. Choose another photo.",
            requestID: requestID
        )
    }

    private func fail(_ message: String, requestID: Int) {
        guard isCurrent(requestID) else { return }
        readingTask = nil
        phase = .failed(message)
    }

    /// Pairs every panel with the block it was read from.
    ///
    /// Each block is assembled on its own through the same function the whole
    /// reading used, so the pairing cannot drift from how the sign was really
    /// put together. A block that produced two panels contributes both, each
    /// carrying that block's box.
    private static func plateItems(from reading: SignReading) -> [PlateItem] {
        var items: [PlateItem] = []
        for block in reading.blocks {
            for result in SignVision.assemble([block]).panels {
                items.append(
                    PlateItem(
                        id: items.count,
                        result: result,
                        sourceBox: block.boundingBox
                    )
                )
            }
        }
        return items
    }

    private func refreshEvaluation() {
        guard let sign else { return }
        let evaluation = Evaluator.evaluate(sign, at: Date(), in: timeZone)
        phase = .result(evaluation)
        scheduleRefresh(for: evaluation.nextChange)
    }

    private func scheduleRefresh(for change: Change?) {
        refreshTask?.cancel()
        guard let change else { return }
        let nanoseconds = UInt64(max(0, change.at.timeIntervalSinceNow + 0.05) * 1_000_000_000)
        refreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            self?.refreshEvaluation()
        }
    }
}

private extension UIImage.Orientation {
    var cgImageOrientation: CGImagePropertyOrientation {
        switch self {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .upMirrored: .upMirrored
        case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}
