import CoreGraphics
import Foundation
import ImageIO
import SignKit
import SignVision

// A development tool for running a real photograph through the same pipeline
// the app uses, and printing the evidence behind every decision.
//
// It exists because the SignVision tests draw their own images. Synthetic
// arrows pass gates that photographed arrows do not, so a passing suite proves
// nothing about a photograph until one has actually been through here.

guard CommandLine.arguments.count > 1 else {
    print("usage: signlook <path to photograph>")
    exit(2)
}

let path = CommandLine.arguments[1]
let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)

guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
else {
    FileHandle.standardError.write(Data("could not read an image at \(url.path)\n".utf8))
    exit(1)
}

// A photograph off a phone carries its rotation in metadata rather than in the
// pixels. Reading it the wrong way up would defeat every shape test, so the
// stored orientation is passed through rather than assumed upright.
let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
let orientationValue = properties?[kCGImagePropertyOrientation] as? UInt32 ?? 1
let orientation = CGImagePropertyOrientation(rawValue: orientationValue) ?? .up

print("image        \(image.width) x \(image.height)")
print("orientation  \(orientationValue) (\(describe(orientation)))")
print("")

let recogniser = SignRecognizer()
let semaphore = DispatchSemaphore(value: 0)
nonisolated(unsafe) var outcome: Result<SignReading, Error>?

// Detached on purpose. Top level code in main.swift runs on the main actor, so
// a plain Task would inherit it and then wait on a semaphore the main thread is
// already blocking, which deadlocks before the pipeline ever starts.
Task.detached(priority: .userInitiated) {
    do {
        outcome = .success(try await recogniser.read(image, orientation: orientation))
    } catch {
        outcome = .failure(error)
    }
    semaphore.signal()
}
semaphore.wait()

switch outcome {
case .failure(let error):
    print("the pipeline failed: \(error.localizedDescription)")
    exit(1)
case .none:
    print("the pipeline returned nothing at all")
    exit(1)
case .success(let reading):
    report(reading)
}

func report(_ reading: SignReading) {
    print("pipeline v\(reading.pipelineVersion), \(reading.blocks.count) block(s)")
    print("")

    // Arrow detection only searches inside a region whose colour is trusted,
    // so an empty or colourless list here is the reason no arrow was found.
    print("Candidate sign faces (\(reading.regions.count))")
    if reading.regions.isEmpty {
        print("  none. no arrow can be found without one.")
    }
    for (index, region) in reading.regions.enumerated() {
        let trusted = region.colourEvidence.supportsStandalonePanel
            && (region.colourHint == .red || region.colourHint == .green)
        print("  \(index + 1). colour \(region.colourHint.rawValue)  "
            + "standalone \(region.colourEvidence.supportsStandalonePanel)  "
            + "searched for arrows: \(trusted ? "yes" : "no")")
        print("     \(format(region.boundingBox))")
    }
    print("")

    for (index, block) in reading.blocks.enumerated() {
        print("Block \(index + 1)")
        print("  colour           \(block.colourHint.rawValue)")
        print("  arrow            \(block.visualDirection?.rawValue ?? "none found")")
        print("  box              \(format(block.boundingBox))")
        print("  text observations \(block.lines.count)")
        for line in block.lines {
            print("    \"\(line.text)\"  confidence \(String(format: "%.2f", line.confidence))")
        }
        print("")
    }

    print("Panels")
    if reading.sign.panels.isEmpty {
        print("  none")
    }
    for (index, result) in reading.sign.panels.enumerated() {
        switch result {
        case .panel(let panel):
            print("  \(index + 1). \(Wording.describe(panel))")
            print("     direction: \(panel.direction.rawValue)")
        case .unknown(let unknown):
            print("  \(index + 1). Not read. \(Wording.describe(unknown.reason))")
        }
    }
}

func format(_ rect: CGRect) -> String {
    String(
        format: "x %.3f  y %.3f  w %.3f  h %.3f",
        rect.origin.x, rect.origin.y, rect.width, rect.height
    )
}

func describe(_ orientation: CGImagePropertyOrientation) -> String {
    switch orientation {
    case .up: "up"
    case .upMirrored: "up mirrored"
    case .down: "down"
    case .downMirrored: "down mirrored"
    case .leftMirrored: "left mirrored"
    case .right: "right"
    case .rightMirrored: "right mirrored"
    case .left: "left"
    @unknown default: "unknown"
    }
}
