import Foundation
import ImageIO
import SignKit
import SignVision
import UIKit

@MainActor
final class SignViewModel: ObservableObject {
    enum Phase {
        case ready
        case reading
        case result(Evaluation)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .ready

    private let recognizer: SignRecognizer
    private let timeZone: TimeZone
    private var sign: Sign?
    private var refreshTask: Task<Void, Never>?

    init(
        recognizer: SignRecognizer = SignRecognizer(),
        timeZone: TimeZone = TimeZone(identifier: "Australia/Sydney")!
    ) {
        self.recognizer = recognizer
        self.timeZone = timeZone
    }

    func read(_ image: UIImage) {
        guard let cgImage = image.cgImage else {
            phase = .failed("The camera did not return a readable photograph.")
            return
        }

        refreshTask?.cancel()
        phase = .reading
        Task {
            do {
                let reading = try await recognizer.read(
                    cgImage,
                    orientation: image.imageOrientation.cgImageOrientation
                )
                sign = reading.sign
                refreshEvaluation()
            } catch {
                phase = .failed(
                    (error as? LocalizedError)?.errorDescription
                        ?? "The photograph could not be read."
                )
            }
        }
    }

    func reset() {
        refreshTask?.cancel()
        sign = nil
        phase = .ready
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
