import Foundation
import ScreenerCore

/// Development-time trace entry point. Capture backends are added in the next milestone.
public actor Screener {
    private var writer: TraceBundleWriter?
    private var isTransitioning = false

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

public enum ScreenerError: Error, Equatable {
    case sessionAlreadyActive
    case noActiveSession
    case sessionTransitionInProgress
}
