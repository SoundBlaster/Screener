import Foundation
import CoreGraphics
import ImageIO
import ScreenerCore

/// Development-time trace entry point for semantic markers and captured keyframes.
public actor Screener {
    private var writer: TraceBundleWriter?
    private var isTransitioning = false
    private let imageEncoder = PNGImageEncoder()

    public init() {}

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
        try await writer.append(kind: .marker, name: name, metadata: metadata)
    }

    /// Encodes and stores a captured image away from the UI actor, then appends its frame record.
    public func recordFrame(_ image: CapturedImage, reason: String) async throws {
        guard !isTransitioning else { throw ScreenerError.sessionTransitionInProgress }
        guard let writer else { throw ScreenerError.noActiveSession }

        let pngData = try await imageEncoder.encodePNG(image.cgImage)
        let blob = try await writer.writeBlob(pngData, kind: .frame, fileExtension: "png")
        try await writer.append(
            kind: .keyframe,
            name: reason,
            metadata: [
                "pixelWidth": String(image.cgImage.width),
                "pixelHeight": String(image.cgImage.height),
                "scale": String(image.scale),
                "encoding": "png",
            ],
            blob: blob
        )
    }

    public func stopSession() async throws {
        guard !isTransitioning else { throw ScreenerError.sessionTransitionInProgress }
        guard let writer else { throw ScreenerError.noActiveSession }
        self.writer = nil
        isTransitioning = true
        do {
            try await writer.append(kind: .sessionEnded, name: "session-ended")
            await writer.close()
            isTransitioning = false
        } catch {
            await writer.close()
            isTransitioning = false
            throw error
        }
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

private actor PNGImageEncoder {
    func encodePNG(_ image: CGImage) throws -> Data {
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
