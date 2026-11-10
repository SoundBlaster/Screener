import Foundation
import CoreGraphics
#if os(macOS)
import AppKit
import ScreenCaptureKit
#endif
import ScreenerKit
import ScreenerScreenCaptureKit

public struct RecordableWindow: Codable, Sendable, Equatable {
    public let windowID: UInt32
    public let processID: Int32
    public let appBundleID: String
    public let title: String

    public init(windowID: UInt32, processID: Int32, appBundleID: String, title: String) {
        self.windowID = windowID
        self.processID = processID
        self.appBundleID = appBundleID
        self.title = title
    }
}

public protocol WindowCaptureProvider: Sendable {
    @MainActor func windows(appBundleID: String) async throws -> [RecordableWindow]
    @MainActor func capture(windowID: UInt32, processID: Int32) async throws -> CapturedImage
}

#if os(macOS)
@available(macOS 14, *)
public struct SystemWindowCaptureProvider: WindowCaptureProvider {
    public init() {}

    @MainActor public func windows(appBundleID: String) async throws -> [RecordableWindow] {
        guard ScreenCaptureKitWindowSource.isAuthorized else { throw WindowRecordingError.permissionRequired }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        return content.windows.compactMap { window in
            guard let owner = window.owningApplication, owner.bundleIdentifier == appBundleID else { return nil }
            return RecordableWindow(windowID: window.windowID, processID: owner.processID,
                                    appBundleID: owner.bundleIdentifier, title: window.title ?? "")
        }
    }

    @MainActor public func capture(windowID: UInt32, processID: Int32) async throws -> CapturedImage {
        // A command-line MCP process may not yet have a WindowServer connection.
        _ = NSApplication.shared
        return try await ScreenCaptureKitWindowSource(windowID: windowID, processID: processID).capture()
    }
}
#endif

public enum WindowRecordingError: Error, LocalizedError, Equatable {
    case permissionRequired, invalidArgument, alreadyActive, noActiveSession, wrongSession, busy, windowUnavailable, captureLimit

    public var errorDescription: String? {
        switch self {
        case .permissionRequired: "Screen Recording permission is required for the server process."
        case .invalidArgument: "Invalid window, application, session name, or capture reason."
        case .alreadyActive: "A window recording session is already active."
        case .noActiveSession: "No window recording session is active."
        case .wrongSession: "The requested session is not the active window recording."
        case .busy: "Another window recording operation is in progress."
        case .windowUnavailable: "The selected window and process are not available for the requested application."
        case .captureLimit: "The recording has reached its capture limit."
        }
    }
}

public struct WindowRecordingSession: Codable, Sendable, Equatable {
    public let sessionID: UUID
    public let windowID: UInt32
    public let processID: Int32
    public let appBundleID: String
    public let capturedFrames: Int
}

/// Serializes explicit capture requests. No timer or background capture is started.
public actor WindowRecordingController {
    private struct Active {
        let recorder: Screener
        let sessionID: UUID
        let window: RecordableWindow
        var capturedFrames: Int
    }

    private let root: URL
    private let provider: any WindowCaptureProvider
    private var active: Active?
    private var busy = false
    private let maximumFrames = 256

    public init(root: URL, provider: any WindowCaptureProvider) {
        self.root = root
        self.provider = provider
    }

    public func windows(appBundleID: String) async throws -> [RecordableWindow] {
        guard validText(appBundleID) else { throw WindowRecordingError.invalidArgument }
        return try await provider.windows(appBundleID: appBundleID)
    }

    public func start(appBundleID: String, windowID: UInt32, processID: Int32, name: String) async throws -> WindowRecordingSession {
        guard validText(appBundleID), validText(name), windowID > 0, processID > 0 else { throw WindowRecordingError.invalidArgument }
        guard !busy else { throw WindowRecordingError.busy }
        guard active == nil else { throw WindowRecordingError.alreadyActive }
        busy = true
        defer { busy = false }
        let windows = try await provider.windows(appBundleID: appBundleID)
        guard let window = windows.first(where: { $0.windowID == windowID && $0.processID == processID && $0.appBundleID == appBundleID }) else {
            throw WindowRecordingError.windowUnavailable
        }
        let recorder = Screener()
        let url = try await recorder.startSession(name: name, appBundleID: appBundleID, tracesDirectory: root)
        guard let sessionID = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else {
            try await recorder.stopSession()
            throw WindowRecordingError.invalidArgument
        }
        let session = Active(recorder: recorder, sessionID: sessionID, window: window, capturedFrames: 0)
        active = session
        return info(session)
    }

    public func capture(sessionID: UUID, reason: String) async throws -> WindowRecordingSession {
        guard validText(reason) else { throw WindowRecordingError.invalidArgument }
        guard !busy else { throw WindowRecordingError.busy }
        guard var session = active else { throw WindowRecordingError.noActiveSession }
        guard session.sessionID == sessionID else { throw WindowRecordingError.wrongSession }
        guard session.capturedFrames < maximumFrames else { throw WindowRecordingError.captureLimit }
        busy = true
        defer { busy = false }
        let windows = try await provider.windows(appBundleID: session.window.appBundleID)
        guard windows.contains(where: { $0.windowID == session.window.windowID && $0.processID == session.window.processID && $0.appBundleID == session.window.appBundleID }) else {
            throw WindowRecordingError.windowUnavailable
        }
        let image = try await provider.capture(windowID: session.window.windowID, processID: session.window.processID)
        try await session.recorder.recordFrame(image, reason: reason, metadata: [
            "capture.backend": "ScreenCaptureKit.window", "capture.windowID": String(session.window.windowID),
            "capture.processID": String(session.window.processID),
        ])
        session.capturedFrames += 1
        active = session
        return info(session)
    }

    public func stop(sessionID: UUID) async throws -> WindowRecordingSession {
        guard !busy else { throw WindowRecordingError.busy }
        guard let session = active else { throw WindowRecordingError.noActiveSession }
        guard session.sessionID == sessionID else { throw WindowRecordingError.wrongSession }
        busy = true
        defer { busy = false }
        active = nil
        try await session.recorder.stopSession()
        return info(session)
    }

    private func info(_ session: Active) -> WindowRecordingSession {
        WindowRecordingSession(sessionID: session.sessionID, windowID: session.window.windowID,
                               processID: session.window.processID, appBundleID: session.window.appBundleID,
                               capturedFrames: session.capturedFrames)
    }

    private func validText(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.utf8.count <= 160
    }
}
