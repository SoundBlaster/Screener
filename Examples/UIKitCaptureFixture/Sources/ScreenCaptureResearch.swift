#if canImport(ScreenCaptureKit) && !targetEnvironment(simulator)
import UIKit
import ScreenCaptureKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import ScreenerKit

/// Device-only experiment. Captures synthetic fixture content after system consent.
@available(iOS 27, *)
@MainActor
final class ScreenCaptureResearch: NSObject, SCContentSharingPickerObserver, SCStreamDelegate {
    private enum State { case picking, starting, running, stopping, finished }
    private var state = State.picking
    private let window: UIWindow
    private let root: URL
    private let sink: ScreenCaptureResearchSink
    private var stream: SCStream?
    private var deadline: Task<Void, Never>?
    private var hierarchyTask: Task<Void, Never>?
    private let statusLabel = UILabel(frame: CGRect(x: 24, y: 664, width: 340, height: 44))

    init(window: UIWindow) {
        self.window = window
        root = URL.documentsDirectory.appending(path: "ScreenCaptureResearch/\(UUID().uuidString)", directoryHint: .isDirectory)
        sink = ScreenCaptureResearchSink(root: root)
        super.init()
        statusLabel.text = "picking"
        statusLabel.accessibilityIdentifier = "fixture.captureStatus"
        statusLabel.textColor = .black
        statusLabel.backgroundColor = .white
        window.rootViewController?.view.addSubview(statusLabel)
        let stop = UIButton(type: .system)
        stop.configuration = .borderedProminent()
        stop.setTitle("Stop capture", for: .normal)
        stop.accessibilityIdentifier = "fixture.stopCapture"
        stop.frame = CGRect(x: 24, y: 610, width: 200, height: 44)
        stop.addAction(UIAction { [weak self] _ in
            Task { await self?.stop(reason: "fixture-button") }
        }, for: .touchUpInside)
        window.rootViewController?.view.addSubview(stop)
    }

    func present() {
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try root.lastPathComponent.write(to: root.deletingLastPathComponent().appending(path: "latest-run.txt"), atomically: true, encoding: .utf8)
        } catch { print("ScreenCaptureResearch setup: \(error)"); return }
        let picker = SCContentSharingPicker.shared
        var configuration = SCContentSharingPickerConfiguration()
        configuration.showsMicrophoneControl = false
        configuration.showsCameraControl = false
        picker.defaultConfiguration = configuration
        picker.add(self)
        picker.isActive = true
        log("picker-presented available=\(picker.isAvailable) scale=\(window.traitCollection.displayScale) bounds=\(window.bounds)")
        deadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(180)) } catch { return }
            await self?.stop(reason: "deadline")
        }
        picker.presentForCurrentApplication()
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor in await self.stop(reason: "picker-cancelled") }
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        let selection = SelectedFilter(value: filter)
        Task { @MainActor in await self.start(filter: selection.value) }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: any Error) {
        Task { @MainActor in await self.stop(reason: "picker-error: \(error)") }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        Task { @MainActor in await self.stop(reason: "stream-error: \(error)") }
    }

    private func start(filter: SCContentFilter) async {
        guard state == .picking else { return }
        state = .starting
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = false
        // Observe the default resolution rather than assuming device scale.
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        self.stream = stream
        do {
            try stream.addStreamOutput(sink, type: .screen, sampleHandlerQueue: sink.queue)
            try await stream.startCapture()
            guard state == .starting else { try? await stream.stopCapture(); return }
            state = .running
            statusLabel.text = "running"
            log("started isCapturing=\(stream.isCapturing) filterRect=\(filter.contentRect)")
            sink.beginPublishing()
            hierarchyTask = Task { [weak self] in
                var publication = 0
                while !Task.isCancelled {
                    guard let self, self.state == .running else { return }
                    do {
                        let image = try UIKitCaptureSource(view: self.window).capture()
                        try UIImage(cgImage: image.cgImage).pngData()?.write(to: self.root.appending(path: "adapter.png"), options: .atomic)
                        let name = String(format: "adapter-%02d", publication % 16)
                        try UIImage(cgImage: image.cgImage).pngData()?.write(to: self.root.appending(path: name + ".png"), options: .atomic)
                        try Date().ISO8601Format().write(to: self.root.appending(path: name + ".txt"), atomically: true, encoding: .utf8)
                        publication += 1
                        try await Task.sleep(for: .seconds(2))
                    } catch { self.log("hierarchy: \(error)"); return }
                }
            }
        } catch { await stop(reason: "start-error: \(error)") }
    }

    private func stop(reason: String) async {
        guard state != .stopping && state != .finished else { return }
        state = .stopping
        log("stopping reason=\(reason)")
        deadline?.cancel()
        hierarchyTask?.cancel()
        if let stream {
            do { try await stream.stopCapture(); log("stopped isCapturing=\(stream.isCapturing)") }
            catch { log("stop-error: \(error)") }
        }
        SCContentSharingPicker.shared.remove(self)
        SCContentSharingPicker.shared.isActive = false
        await sink.finish()
        state = .finished
        statusLabel.text = "finished"
        log("finished pickerActive=\(SCContentSharingPicker.shared.isActive)")
    }

    private func log(_ message: String) {
        print("ScreenCaptureResearch \(message)")
        let url = root.appending(path: "events.txt")
        let previous = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        try? (previous + "\(Date().ISO8601Format()) \(message)\n").write(to: url, atomically: true, encoding: .utf8)
    }
}

// The iOS filter exposes read-only selection properties. The observer hands this
// immutable snapshot to MainActor and never accesses it again; the SDK does not
// declare SCContentFilter Sendable, so keep that narrow interop boundary explicit.
@available(iOS 27, *)
private struct SelectedFilter: @unchecked Sendable {
    let value: SCContentFilter
}

/// All mutable state and image encoding are confined to `queue`, which is also
/// passed to SCStream as its output queue. Public operations enqueue on that queue.
/// At most one retained complete frame and one PNG publication per second.
@available(iOS 27, *)
private final class ScreenCaptureResearchSink: NSObject, SCStreamOutput, @unchecked Sendable {
    let queue = DispatchQueue(label: "screener.research.screen-frames", qos: .utility)
    private let root: URL
    private let context = CIContext()
    private var pending: CVPixelBuffer?
    private var metadata: [String: Any] = [:]
    private var callbacks = 0
    private var completeFrames = 0
    private var publications = 0
    private var stopped = false

    init(root: URL) { self.root = root }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !stopped, type == .screen else { return }
        callbacks += 1
        guard sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let info = attachments.first,
              let status = info[.status] as? Int,
              status == SCFrameStatus.complete.rawValue,
              let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        completeFrames += 1
        pending = pixels
        metadata = ["presentationSeconds": sampleBuffer.presentationTimeStamp.seconds,
                    "width": CVPixelBufferGetWidth(pixels), "height": CVPixelBufferGetHeight(pixels),
                    "pixelFormat": CVPixelBufferGetPixelFormatType(pixels), "status": status]
        for key in [SCStreamFrameInfo.scaleFactor, .contentScale, .contentRect, .screenRect, .videoOrientation] {
            if let value = info[key] { metadata[key.rawValue] = String(describing: value) }
        }
    }

    func beginPublishing() { queue.async { self.publishAndSchedule() } }

    private func publishAndSchedule() {
        guard !stopped else { return }
        publish()
        queue.asyncAfter(deadline: .now() + 1) { self.publishAndSchedule() }
    }

    private func publish() {
        guard let pixels = pending else { return }
        // Retain only the latest complete sample; static final frames survive thinning.
        pending = nil
        let started = ContinuousClock.now
        let image = CIImage(cvPixelBuffer: pixels)
        guard let cgImage = context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)),
              let data = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { return }
        do {
            try (data as Data).write(to: root.appending(path: "stream.png"), options: .atomic)
            publications += 1
            metadata["callbacks"] = callbacks
            metadata["completeFrames"] = completeFrames
            metadata["publications"] = publications
            metadata["publicationTime"] = Date().ISO8601Format()
            metadata["encodingDuration"] = String(describing: started.duration(to: .now))
            let metadataData = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
            try metadataData.write(to: root.appending(path: "stream.json"), options: .atomic)
            let name = String(format: "stream-%02d", publications % 32)
            try (data as Data).write(to: root.appending(path: name + ".png"), options: .atomic)
            try metadataData.write(to: root.appending(path: name + ".json"), options: .atomic)
        } catch { writeError(error) }
    }

    func finish() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.stopped = true
                self.publish()
                let summary = ["callbacks": self.callbacks, "completeFrames": self.completeFrames, "publications": self.publications]
                do {
                    try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys])
                        .write(to: self.root.appending(path: "summary.json"), options: .atomic)
                } catch { self.writeError(error) }
                continuation.resume()
            }
        }
    }

    private func writeError(_ error: any Error) {
        try? String(describing: error).write(to: root.appending(path: "encoding-error.txt"), atomically: true, encoding: .utf8)
    }
}
#endif
