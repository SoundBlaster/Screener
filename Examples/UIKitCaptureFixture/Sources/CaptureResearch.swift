import UIKit
import ReplayKit
import CoreImage
import ScreenerKit

/// Opt-in, synthetic-content experiments. Does not change ScreenerKit's backend.
@MainActor
enum CaptureResearch {
    static func run(window: UIWindow) async {
        let root = URL.documentsDirectory.appending(path: "CaptureResearch", directoryHint: .isDirectory)
        let replayKit = RPScreenRecorder.shared()
        let sink = ReplayKitResearchSink(root: root)
        var startedReplayKit = false
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            if ProcessInfo.processInfo.arguments.contains("--replaykit-probe") {
                if replayKit.isAvailable {
                    do {
                        replayKit.isMicrophoneEnabled = false
                        replayKit.isCameraEnabled = false
                        try await replayKit.startCapture { buffer, type, error in
                            sink.consume(buffer, type: type, error: error)
                        }
                        startedReplayKit = true
                        try "started".write(to: root.appending(path: "replaykit-status.txt"), atomically: true, encoding: .utf8)
                    } catch {
                        try String(describing: error).write(to: root.appending(path: "replaykit-status.txt"), atomically: true, encoding: .utf8)
                    }
                } else {
                    try "isAvailable=false".write(to: root.appending(path: "replaykit-status.txt"), atomically: true, encoding: .utf8)
                }
            }
            // Capture only latest variants: bounded time and bounded disk use.
            let requestedPasses = ProcessInfo.processInfo.arguments
                .first(where: { $0.hasPrefix("--research-passes=") })
                .flatMap { Int($0.dropFirst("--research-passes=".count)) } ?? 40
            let deadline = ContinuousClock.now.advanced(by: .seconds(120))
            for pass in 0..<min(40, max(1, requestedPasses)) {
                guard ContinuousClock.now < deadline else { break }
                try await Task.sleep(for: .seconds(3))
                var metadata: [String: Any] = ["pass": pass, "displayScale": window.traitCollection.displayScale]
                let image = try UIKitCaptureSource(view: window).capture()
                try save(image.cgImage, to: root.appending(path: "adapter.png"))
                for (name, updates, range) in [
                    ("hierarchy-false", false, UIGraphicsImageRendererFormat.Range.automatic),
                    ("hierarchy-standard", true, .standard),
                    ("hierarchy-extended", true, .extended),
                ] {
                    let format = UIGraphicsImageRendererFormat()
                    format.scale = window.traitCollection.displayScale
                    format.opaque = window.isOpaque
                    format.preferredRange = range
                    var complete = false
                    let output = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
                        complete = window.drawHierarchy(in: window.bounds, afterScreenUpdates: updates)
                    }
                    metadata[name] = ["complete": complete, "bitsPerComponent": output.cgImage?.bitsPerComponent ?? 0]
                    if let cgImage = output.cgImage { try save(cgImage, to: root.appending(path: name + ".png")) }
                }
                let format = UIGraphicsImageRendererFormat()
                format.scale = window.traitCollection.displayScale
                let layerImage = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { context in
                    window.layer.render(in: context.cgContext)
                }
                if let cgImage = layerImage.cgImage { try save(cgImage, to: root.appending(path: "layer.png")) }
                if let snapshot = window.snapshotView(afterScreenUpdates: true) {
                    var complete = false
                    let output = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
                        complete = snapshot.drawHierarchy(in: snapshot.bounds, afterScreenUpdates: false)
                    }
                    metadata["snapshot-hierarchy"] = ["complete": complete]
                    if let cgImage = output.cgImage { try save(cgImage, to: root.appending(path: "snapshot-hierarchy.png")) }
                }
                let windows = window.windowScene?.windows.filter { !$0.isHidden && $0.alpha > 0 } ?? [window]
                var complete = true
                let sceneImage = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { context in
                    for candidate in windows.sorted(by: { $0.windowLevel < $1.windowLevel }) {
                        context.cgContext.saveGState()
                        let rect = window.convert(candidate.bounds, from: candidate)
                        complete = candidate.drawHierarchy(in: rect, afterScreenUpdates: true) && complete
                        context.cgContext.restoreGState()
                    }
                }
                metadata["scene-windows"] = ["count": windows.count, "complete": complete]
                if let cgImage = sceneImage.cgImage { try save(cgImage, to: root.appending(path: "scene-windows.png")) }
                try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
                    .write(to: root.appending(path: "latest.json"), options: .atomic)
            }
            try "finished".write(to: root.appending(path: "finished.txt"), atomically: true, encoding: .utf8)
        } catch {
            try? String(describing: error).write(to: root.appending(path: "error.txt"), atomically: true, encoding: .utf8)
        }
        sink.finish()
        // Stop even when rendering, disk writes, or cancellation fail.
        if startedReplayKit {
            do {
                try? "stopping".write(to: root.appending(path: "replaykit-stop.txt"), atomically: true, encoding: .utf8)
                try await replayKit.stopCapture()
                try? "stopped".write(to: root.appending(path: "replaykit-stop.txt"), atomically: true, encoding: .utf8)
            } catch {
                try? String(describing: error).write(to: root.appending(path: "replaykit-stop-error.txt"), atomically: true, encoding: .utf8)
            }
        }
    }

    private static func save(_ image: CGImage, to url: URL) throws {
        guard let data = UIImage(cgImage: image).pngData() else { throw ScreenerCaptureError.encodingFailed }
        try data.write(to: url, options: .atomic)
    }
}

/// ReplayKit invokes its sample callback off the main actor.
private final class ReplayKitResearchSink: @unchecked Sendable {
    private let root: URL
    private let lock = NSLock()
    private var lastWrite = -Double.infinity
    private var frameCount = 0
    private var callbackCount = 0
    private var videoCallbackCount = 0
    private var convertedFrameCount = 0
    private let context = CIContext()

    init(root: URL) { self.root = root }

    func consume(_ buffer: CMSampleBuffer, type: RPSampleBufferType, error: Error?) {
        lock.lock()
        defer { lock.unlock() }
        callbackCount += 1
        if type == .video { videoCallbackCount += 1 }
        if let error {
            try? String(describing: error).write(to: root.appending(path: "replaykit-error.txt"), atomically: true, encoding: .utf8)
            return
        }
        guard type == .video, let pixels = CMSampleBufferGetImageBuffer(buffer) else { return }
        frameCount += 1
        let timestamp = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
        guard timestamp - lastWrite >= 2 else { return }
        lastWrite = timestamp
        let image = CIImage(cvPixelBuffer: pixels)
        guard let cgImage = context.createCGImage(image, from: image.extent) else { return }
        convertedFrameCount += 1
        do {
            try UIImage(cgImage: cgImage).pngData()?.write(to: root.appending(path: "replaykit.png"), options: .atomic)
            let info: [String: Any] = ["framesReceived": frameCount, "width": cgImage.width, "height": cgImage.height, "presentationSeconds": timestamp]
            try JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys])
                .write(to: root.appending(path: "replaykit.json"), options: .atomic)
        } catch {
            try? String(describing: error).write(to: root.appending(path: "replaykit-error.txt"), atomically: true, encoding: .utf8)
        }
    }

    func finish() {
        lock.lock()
        defer { lock.unlock() }
        let info = ["callbacks": callbackCount, "videoCallbacks": videoCallbackCount,
                    "framesWithPixelBuffer": frameCount, "convertedFrames": convertedFrameCount]
        if let data = try? JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: root.appending(path: "replaykit-summary.json"), options: .atomic)
        }
    }
}
