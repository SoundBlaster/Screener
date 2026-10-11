#if SCREENER_SCREENSHOTS
import Foundation
import ScreenerKit
import UIKit
import SwiftUI

/// Simulator-only checkpoint protocol. Each recorder belongs to its probe's window.
@MainActor
final class ScreenshotRecorder {
    static let sessionSeconds = 180.0
    static let requestSeconds = 12.0
    static let settleSeconds = 0.8
    static let maximumFrames = 16
    var isReady = false
    var presentation = "main"
    private weak var window: UIWindow?
    private var task: Task<Void, Never>?

    static var runID: UUID? {
        UUID(uuidString: ProcessInfo.processInfo.environment["SCREENER_RUN_ID"] ?? "")
    }

    static var isActivated: Bool {
        #if targetEnvironment(simulator)
        let isSimulator = true
        #else
        let isSimulator = false
        #endif
        return isSimulator && runID != nil && ProcessInfo.processInfo.environment["SCREENER_SCREENSHOTS"] == "1"
    }

    func attach(to newWindow: UIWindow?) {
        guard window !== newWindow else { return }
        task?.cancel()
        window = newWindow
        guard let newWindow, Self.isActivated, let runID = Self.runID else { return }
        task = Task { [weak self, weak newWindow] in
            guard let self, let newWindow else { return }
            await record(window: newWindow, runID: runID)
        }
    }

    private func record(window: UIWindow, runID: UUID) async {
        let screener = Screener()
        var directory: URL?
        do {
            let caches = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let run = caches.appending(path: "Screener/Screenshots/\(runID.uuidString)", directoryHint: .isDirectory)
            directory = run
            try FileManager.default.createDirectory(at: run, withIntermediateDirectories: true)
            let trace = try await screener.startSession(
                name: "App Store screenshot checkpoints", appBundleID: Bundle.main.bundleIdentifier ?? "ScreenshotApp",
                tracesDirectory: run
            )
            try await screener.mark("screenshots.ready", metadata: [
                "backend": "UIKitCaptureSource", "runID": runID.uuidString,
                "orientation": ProcessInfo.processInfo.environment["SCREENER_ORIENTATION"] ?? "unknown"
            ])
            try write(["state": "ready", "trace": trace.lastPathComponent], to: run.appending(path: "ready.json"))
            let started = ContinuousClock.now
            var frames = 0
            let command = run.appending(path: "request.json")
            while !Task.isCancelled && seconds(since: started) < Self.sessionSeconds {
                if let data = try? Data(contentsOf: command) {
                    let request = try JSONDecoder().decode(Request.self, from: data)
                    try FileManager.default.removeItem(at: command)
                    if request.name == "stop" {
                        try await screener.stopSession()
                        try write(["state": "stopped"], to: run.appending(path: "stopped.json"))
                        return
                    }
                    guard frames < Self.maximumFrames else { throw CaptureError.tooManyCheckpoints }
                    try await captureAndRespond(request, window: window, screener: screener, run: run)
                    frames += 1
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            throw CaptureError.sessionExpired
        } catch is CancellationError {
            // Detaching the probe cancels polling and still closes the trace.
        } catch {
            if let directory {
                try? write(["state": "failed", "error": String(describing: error)], to: directory.appending(path: "failure.json"))
            }
        }
        try? await screener.stopSession()
    }

    private func captureAndRespond(_ request: Request, window: UIWindow, screener: Screener, run: URL) async throws {
        do {
            try await capture(request, window: window, screener: screener)
            try write(["state": "complete", "name": request.name], to: run.appending(path: "response.json"))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try await screener.mark("screenshots.failure", metadata: ["name": request.name, "error": String(describing: error)])
            try write(["state": "failed", "name": request.name, "error": String(describing: error)],
                      to: run.appending(path: "response.json"))
            throw error
        }
    }

    private func capture(_ request: Request, window: UIWindow, screener: Screener) async throws {
        let started = ContinuousClock.now
        var stableSince = ContinuousClock.now
        var previousBounds = window.bounds
        var previousPresentation = presentation
        var previousScale = window.traitCollection.displayScale
        while seconds(since: started) < Self.requestSeconds {
            try Task.checkCancellation()
            let active = window.windowScene?.activationState == .foregroundActive
            let matches = presentation == request.presentation
            if previousBounds != window.bounds || previousPresentation != presentation
                || previousScale != window.traitCollection.displayScale || !isReady || !active || !matches {
                stableSince = .now
            }
            previousBounds = window.bounds
            previousPresentation = presentation
            previousScale = window.traitCollection.displayScale
            if isReady && active && matches && seconds(since: stableSince) >= Self.settleSeconds {
                let image = try UIKitCaptureSource(view: window).capture()
                let expectedWidth = Int((window.bounds.width * window.traitCollection.displayScale).rounded())
                let expectedHeight = Int((window.bounds.height * window.traitCollection.displayScale).rounded())
                guard image.cgImage.width == expectedWidth, image.cgImage.height == expectedHeight else {
                    throw CaptureError.nonNativePixels
                }
                try await screener.mark("screenshots.checkpoint", metadata: [
                    "name": request.name, "presentation": presentation,
                    "pointWidth": String(Double(window.bounds.width)), "pointHeight": String(Double(window.bounds.height)),
                    "scale": String(image.scale), "settleSeconds": String(Self.settleSeconds)
                ])
                try await screener.recordFrame(image, reason: request.name, metadata: [
                    "capture.backend": "UIKitCaptureSource", "capture.bitDepth": String(image.cgImage.bitsPerComponent),
                    "capture.colorSpace": (image.cgImage.colorSpace?.name as String?) ?? "unknown",
                    "capture.alphaInfo": String(image.cgImage.alphaInfo.rawValue)
                ])
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw CaptureError.presentationDidNotSettle
    }

    private func write(_ value: [String: String], to url: URL) throws {
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
    }

    private func seconds(since start: ContinuousClock.Instant) -> Double {
        let duration = start.duration(to: .now).components
        return Double(duration.seconds) + Double(duration.attoseconds) / 1e18
    }

    private struct Request: Decodable {
        let name: String
        let presentation: String
    }

    private enum CaptureError: Error {
        case presentationDidNotSettle, nonNativePixels, sessionExpired, tooManyCheckpoints
    }
}
/// Supply app policy results; this adapter only handles capture mechanics.
struct ScreenshotProbe: UIViewRepresentable {
    let isReady: Bool
    let presentation: String
    func makeUIView(context: Context) -> ProbeView { ProbeView() }
    func updateUIView(_ view: ProbeView, context: Context) {
        view.recorder.isReady = isReady
        view.recorder.presentation = presentation
    }
    static func dismantleUIView(_ view: ProbeView, coordinator: ()) { view.recorder.attach(to: nil) }
    final class ProbeView: UIView {
        let recorder = ScreenshotRecorder()
        override func didMoveToWindow() {
            super.didMoveToWindow()
            recorder.attach(to: window)
        }
    }
}
#endif
