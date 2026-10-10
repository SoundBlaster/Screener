#if os(iOS) && canImport(ScreenCaptureKit) && !targetEnvironment(simulator) && !targetEnvironment(macCatalyst)
import Foundation
import ScreenCaptureKit
import CoreImage
import ImageIO

/// Experimental, current-application capture on a physical iOS 27 device.
/// Retain the session, manually approve the system picker, then call `stop()`
/// before closing the associated Screener trace. Frames are sampled roughly once per second, plus a final drain;
/// this is a keyframe recorder, not a video or transition-rate capture backend.
@available(iOS 27, *)
@MainActor
public final class ScreenCaptureKitSession: NSObject, SCContentSharingPickerObserver, SCStreamDelegate {
    public enum State: Sendable { case idle, awaitingPermission, starting, recording, stopping, finished }
    public enum SessionError: Error, Equatable { case alreadyStarted, pickerBusy, unavailable, permissionCancelled }

    public private(set) var state: State = .idle
    /// Includes asynchronous stream, conversion, and persistence failures.
    public private(set) var failure: (any Error)?
    private static weak var pickerOwner: ScreenCaptureKitSession?
    private let screener: Screener
    private let sink = ScreenFrameSink()
    private var stream: SCStream?
    private var selection: CheckedContinuation<SelectedScreenFilter, Error>?
    private var startup: Task<Void, Error>?
    private var shutdown: Task<Void, Never>?
    private var publisher: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var previousConfiguration: SCContentSharingPickerConfiguration?

    public init(screener: Screener) {
        self.screener = screener
        super.init()
    }

    /// Requires an active trace. Returns when capture starts, throws on rejection
    /// or cancellation. A 180-second bound includes time spent awaiting permission.
    /// Cancellation of the calling task also stops capture and drains accepted frames.
    public func start() async throws {
        guard state == .idle else { throw SessionError.alreadyStarted }
        try Task.checkCancellation()
        let picker = SCContentSharingPicker.shared
        guard Self.pickerOwner == nil, !picker.isActive else { throw SessionError.pickerBusy }
        guard picker.isAvailable else { throw SessionError.unavailable }
        Self.pickerOwner = self
        state = .awaitingPermission
        let task = Task { try await self.begin() }
        startup = task
        do {
            try await withTaskCancellationHandler {
                try await task.value
                try Task.checkCancellation()
            } onCancel: {
                Task { @MainActor in await self.stop() }
            }
        } catch {
            if !(error is CancellationError) { failure = error }
            await stop()
            throw error
        }
    }

    private func begin() async throws {
        // Validate trace lifecycle before presenting a system permission request.
        try await screener.mark("screen-capture.requested")
        try Task.checkCancellation()
        let picker = SCContentSharingPicker.shared
        previousConfiguration = picker.defaultConfiguration
        var configuration = SCContentSharingPickerConfiguration()
        configuration.showsMicrophoneControl = false
        configuration.showsCameraControl = false
        picker.defaultConfiguration = configuration
        picker.add(self)
        picker.isActive = true
        deadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(180)) } catch { return }
            await self?.stop()
        }
        let filter = try await withCheckedThrowingContinuation {
            selection = $0
            picker.presentForCurrentApplication()
        }
        try Task.checkCancellation()
        state = .starting
        sink.setDefaultScale(Double(filter.value.pointPixelScale))
        let configurationForStream = SCStreamConfiguration()
        configurationForStream.capturesAudio = false
        let stream = SCStream(filter: filter.value, configuration: configurationForStream, delegate: self)
        self.stream = stream
        try stream.addStreamOutput(sink, type: .screen, sampleHandlerQueue: sink.queue)
        try await stream.startCapture()
        try Task.checkCancellation()
        state = .recording
        try await screener.mark("screen-capture.started")
        try Task.checkCancellation()
        publisher = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    try await self.publishNext()
                    try await Task.sleep(for: .seconds(1))
                } catch is CancellationError { return }
                catch {
                    self.failure = error
                    // A separate task avoids awaiting the publisher from itself.
                    Task { await self.stop() }
                    return
                }
            }
        }
    }

    /// Idempotent, including during permission/startup. Waits for stream stop and
    /// in-flight writes, then persists the last pending sample. Check `failure`
    /// after stopping; the caller still owns and must close the Screener trace.
    public func stop() async {
        if let shutdown { await shutdown.value; return }
        guard state != .finished else { return }
        state = .stopping
        startup?.cancel()
        selection?.resume(throwing: CancellationError())
        selection = nil
        let task = Task { await self.finish() }
        shutdown = task
        await task.value
    }

    private func finish() async {
        deadline?.cancel()
        // Startup may still be in startCapture(). Stop only after it settles.
        if let startup { _ = await startup.result }
        if let stream {
            do { try await stream.stopCapture() }
            catch { if failure == nil { failure = error } }
        }
        publisher?.cancel()
        await publisher?.value
        sink.close()
        do {
            try await publishNext()
            if startup != nil { try await screener.mark("screen-capture.stopped") }
        } catch { if failure == nil { failure = error } }
        if Self.pickerOwner === self {
            let picker = SCContentSharingPicker.shared
            picker.remove(self)
            picker.isActive = false
            if let previousConfiguration { picker.defaultConfiguration = previousConfiguration }
            Self.pickerOwner = nil
        }
        stream = nil
        startup = nil
        publisher = nil
        deadline = nil
        state = .finished
    }

    private func publishNext() async throws {
        guard let frame = try await sink.take() else { return }
        try await screener.recordFrame(frame.image, reason: "screen-capture.sample", metadata: frame.metadata)
    }

    nonisolated public func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        let snapshot = SelectedScreenFilter(value: filter)
        Task { @MainActor in
            guard self.state == .awaitingPermission else { return }
            self.selection?.resume(returning: snapshot)
            self.selection = nil
        }
    }

    nonisolated public func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor in
            guard self.state == .awaitingPermission else { return }
            self.selection?.resume(throwing: SessionError.permissionCancelled)
            self.selection = nil
        }
    }

    nonisolated public func contentSharingPickerStartDidFailWithError(_ error: any Error) {
        Task { @MainActor in
            self.failure = error
            self.selection?.resume(throwing: error)
            self.selection = nil
            await self.stop()
        }
    }

    nonisolated public func stream(_ stream: SCStream, didStopWithError error: any Error) {
        Task { @MainActor in
            self.failure = error
            await self.stop()
        }
    }
}

// Read-only selection handed to MainActor once; callback never accesses it again.
@available(iOS 27, *)
private struct SelectedScreenFilter: @unchecked Sendable { let value: SCContentFilter }

// Retains an immutable complete sample buffer until conversion on the output queue.
private struct ScreenSample: @unchecked Sendable {
    let pixels: CVPixelBuffer
    let metadata: [String: String]
    let scale: Double
    let orientation: Int32
}

private struct ScreenFrame: Sendable {
    let image: CapturedImage
    let metadata: [String: String]
}

/// Core Image is confined to the output queue. No per-callback Tasks or PNGs;
/// at most one pending sample plus the frame currently being persisted.
@available(iOS 27, *)
private final class ScreenFrameSink: NSObject, SCStreamOutput, @unchecked Sendable {
    let queue = DispatchQueue(label: "screener.screen-capture.frames", qos: .utility)
    private let slot = LatestFrameSlot<ScreenSample>()
    private let context = CIContext()
    private var defaultScale: Double = 1

    func setDefaultScale(_ scale: Double) {
        queue.sync { defaultScale = scale }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let info = attachments.first,
              (info[.status] as? Int) == SCFrameStatus.complete.rawValue,
              let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let scale = (info[.scaleFactor] as? NSNumber)?.doubleValue ?? defaultScale
        let orientation = (info[.videoOrientation] as? NSNumber)?.int32Value ?? 1
        var metadata = ["capture.backend": "ScreenCaptureKit",
                        "capture.presentationSeconds": String(sampleBuffer.presentationTimeStamp.seconds),
                        "capture.pixelFormat": String(CVPixelBufferGetPixelFormatType(pixels)),
                        "capture.orientation": String(orientation), "capture.colorSpace": "sRGB"]
        for key in [SCStreamFrameInfo.scaleFactor, .contentScale, .contentRect, .screenRect] {
            if let value = info[key] { metadata["capture." + key.rawValue] = String(describing: value) }
        }
        slot.offer(ScreenSample(pixels: pixels, metadata: metadata, scale: scale, orientation: orientation))
    }

    func close() { slot.close() }

    func take() async throws -> ScreenFrame? {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    guard let sample = self.slot.take() else { continuation.resume(returning: nil); return }
                    let source = CIImage(cvPixelBuffer: sample.pixels)
                    let oriented = source.oriented(forExifOrientation: sample.orientation)
                    guard let image = self.context.createCGImage(oriented, from: oriented.extent,
                        format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) else {
                        throw ScreenerCaptureError.encodingFailed
                    }
                    let captured = try CapturedImage(cgImage: image, scale: sample.scale)
                    continuation.resume(returning: ScreenFrame(image: captured, metadata: sample.metadata))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
}
#endif
