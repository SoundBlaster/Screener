import Foundation
import CoreGraphics
import ImageIO
import ScreenerCore

/// Development-time trace entry point for semantic markers and captured keyframes.
public actor Screener {
    private var writer: TraceBundleWriter?
    private var isTransitioning = false
    private var operationTail: Task<Void, Error>?
    private let imageEncoder: any PNGImageEncoding

    public init() {
        imageEncoder = PNGImageEncoder()
    }

    init(imageEncoder: any PNGImageEncoding) {
        self.imageEncoder = imageEncoder
    }

    @discardableResult
    public func startSession(
        name: String,
        appBundleID: String,
        tracesDirectory: URL,
        platform: String? = nil
    ) async throws -> URL {
        guard writer == nil else { throw ScreenerError.sessionAlreadyActive }
        guard !isTransitioning else { throw ScreenerError.sessionTransitionInProgress }
        let manifest = TraceManifest(name: name, appBundleID: appBundleID, platform: platform ?? Self.currentPlatform)
        let bundleURL = tracesDirectory.appending(path: "\(manifest.sessionID.uuidString).vtrace")
        let newWriter = try TraceBundleWriter(url: bundleURL, manifest: manifest)
        isTransitioning = true
        writer = newWriter
        do {
            try await newWriter.append(kind: .sessionStarted, name: name)
            isTransitioning = false
        } catch {
            writer = nil
            await newWriter.close()
            isTransitioning = false
            throw error
        }
        return bundleURL
    }

    public func mark(_ name: String, metadata: [String: String] = [:]) async throws {
        guard !isTransitioning else { throw ScreenerError.sessionTransitionInProgress }
        guard let writer else { throw ScreenerError.noActiveSession }
        let timestamp = Date.now
        let monotonicNanoseconds = DispatchTime.now().uptimeNanoseconds
        try await enqueue {
            try await writer.append(
                kind: .marker, name: name, metadata: metadata,
                timestamp: timestamp, monotonicNanoseconds: monotonicNanoseconds
            )
        }
    }

    /// Encodes and stores a captured image away from the UI actor, then appends its frame record.
    /// Additional metadata cannot override the actual PNG dimensions, scale, or encoding.
    public func recordFrame(
        _ image: CapturedImage, reason: String, metadata: [String: String] = [:]
    ) async throws {
        guard !isTransitioning else { throw ScreenerError.sessionTransitionInProgress }
        guard let writer else { throw ScreenerError.noActiveSession }

        let timestamp = Date.now
        let monotonicNanoseconds = DispatchTime.now().uptimeNanoseconds
        let imageEncoder = self.imageEncoder
        try await enqueue {
            let pngData = try await imageEncoder.encodePNG(image.cgImage)
            let blob = try await writer.writeBlob(pngData, kind: .frame, fileExtension: "png")
            try await writer.append(
                kind: .keyframe,
                name: reason,
                metadata: metadata.merging([
                    "pixelWidth": String(image.cgImage.width),
                    "pixelHeight": String(image.cgImage.height),
                    "scale": String(image.scale),
                    "encoding": "png",
                ]) { _, actual in actual },
                blob: blob,
                timestamp: timestamp,
                monotonicNanoseconds: monotonicNanoseconds
            )
        }
    }

    public func stopSession() async throws {
        guard !isTransitioning else { throw ScreenerError.sessionTransitionInProgress }
        guard let writer else { throw ScreenerError.noActiveSession }
        self.writer = nil
        isTransitioning = true
        do {
            try await enqueue {
                try await writer.append(kind: .sessionEnded, name: "session-ended")
                await writer.close()
            }
            isTransitioning = false
        } catch {
            await writer.close()
            isTransitioning = false
            throw error
        }
    }

    /// Reserves timeline order before suspension, so slow encoders cannot reorder later events.
    private func enqueue(_ operation: @escaping @Sendable () async throws -> Void) async throws {
        let previous = operationTail
        let next = Task {
            // A failed event must not prevent later events (especially sessionEnded) from running.
            if let previous { _ = try? await previous.value }
            try await operation()
        }
        operationTail = next
        try await next.value
    }

    private static var currentPlatform: String {
        #if os(iOS)
        "iOS"
        #elseif os(macOS)
        "macOS"
        #else
        "unknown"
        #endif
    }
}

protocol PNGImageEncoding: Sendable {
    func encodePNG(_ image: CGImage) async throws -> Data
}

private actor PNGImageEncoder: PNGImageEncoding {
    func encodePNG(_ image: CGImage) async throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else {
            throw ScreenerCaptureError.encodingFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ScreenerCaptureError.encodingFailed
        }
        return output as Data
    }
}

public enum ScreenerError: Error, Equatable {
    case sessionAlreadyActive
    case noActiveSession
    case sessionTransitionInProgress
}
