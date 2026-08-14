import SignKit
import SwiftUI
import UIKit

struct SignView: View {
    @StateObject private var model = SignViewModel()
    @State private var isCameraPresented = false

    private var cameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Kerbside")
                .toolbar {
                    if case .result = model.phase {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Scan again", systemImage: "camera") {
                                isCameraPresented = true
                            }
                            .disabled(!cameraAvailable)
                        }
                    }
                }
                .fullScreenCover(isPresented: $isCameraPresented) {
                    CameraPicker(isPresented: $isCameraPresented) { image in
                        model.read(image)
                    }
                    .ignoresSafeArea()
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .ready:
            ReadyView(cameraAvailable: cameraAvailable) {
                isCameraPresented = true
            }
        case .reading:
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                Text("Reading sign…")
                    .font(.headline)
                Text("The photograph stays on this device.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        case .result(let evaluation):
            ResultList(evaluation: evaluation)
        case .failed(let message):
            FailureView(message: message, cameraAvailable: cameraAvailable) {
                isCameraPresented = true
            }
        }
    }
}

private struct ReadyView: View {
    let cameraAvailable: Bool
    let openCamera: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 54))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Photograph the whole sign pole")
                    .font(.title2.bold())
                Text("Keep every panel in frame and hold the phone steady.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            Button("Open camera", systemImage: "camera", action: openCamera)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!cameraAvailable)

            if !cameraAvailable {
                Text("A camera is not available. Run Kerbside on a physical iPhone to scan a sign.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ResultList: View {
    let evaluation: Evaluation

    var body: some View {
        List {
            Section("In force now") {
                if evaluation.active.isEmpty {
                    Text("No panel covers this time.")
                        .font(.headline)
                } else {
                    ForEach(Array(evaluation.active.enumerated()), id: \.offset) { item in
                        PanelRow(panel: item.element)
                    }
                }
            }

            if let change = evaluation.nextChange {
                Section("Next change") {
                    NextChangeRow(change: change)
                }
            }

            if !evaluation.inactive.isEmpty {
                Section("Other panels") {
                    ForEach(Array(evaluation.inactive.enumerated()), id: \.offset) { item in
                        PanelRow(panel: item.element)
                    }
                }
            }

            if !evaluation.unknowns.isEmpty {
                Section("Not read") {
                    ForEach(Array(evaluation.unknowns.enumerated()), id: \.offset) { item in
                        UnknownRow(unknown: item.element)
                    }
                }
            }
        }
    }
}

private struct PanelRow: View {
    let panel: Panel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Wording.describe(panel))
                .font(.headline)
            if let direction = Wording.describe(panel.direction) {
                Text(direction)
                    .font(.subheadline)
            }
            Text(panel.rawText)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// Unknown panels use the same title, spacing, and source-text treatment as a
/// parsed panel. They are results, not a secondary error log.
private struct UnknownRow: View {
    let unknown: Unknown

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Panel not read")
                .font(.headline)
            Text(Wording.describe(unknown.reason))
                .font(.subheadline)
            if !unknown.rawText.isEmpty {
                Text(unknown.rawText)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct NextChangeRow: View {
    let change: Change

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(Self.format(change.at), systemImage: "clock")
                .font(.headline)
            Text(changeDescription)
                .font(.subheadline)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private static func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Australia/Sydney")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private var changeDescription: String {
        let verb = change.kind == .begins ? "Begins" : "Ends"
        return "\(verb): \(Wording.describe(change.panel))"
    }
}

private struct FailureView: View {
    let message: String
    let cameraAvailable: Bool
    let tryAgain: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "text.viewfinder")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Sign not read")
                .font(.title2.bold())
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Take another photo", systemImage: "camera", action: tryAgain)
                .buttonStyle(.borderedProminent)
                .disabled(!cameraAvailable)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
