#if os(macOS) && canImport(ScreenCaptureKit)
import CoreGraphics
import Foundation
import ScreenCaptureKit
import ScreenerKit

/// Captures a specific macOS window through the system compositor at native pixels.
/// Requires existing Screen Recording authorization; capture never presents a permission prompt.
/// This async still source does not conform to the synchronous hierarchy-renderer protocol.
@available(macOS 14, *)
@MainActor
public struct ScreenCaptureKitWindowSource {
    /// Failures detected before or after the system screenshot call.
    public enum CaptureError: Error, Equatable {
        /// Screen Recording authorization is absent; the caller must arrange consent.
        case permissionRequired
        /// The requested window and owner are not among the on-screen shareable windows.
        case windowUnavailable
        /// The system reported invalid or nonintegral native geometry.
        case invalidGeometry
        /// The screenshot dimensions differ from the requested native dimensions.
        case unexpectedDimensions
    }

    /// The explicit window identifier; desktop capture is never substituted.
    public let windowID: CGWindowID
    /// The expected window owner, preventing a different process from matching a reused ID.
    public let processID: Int32

    /// Selects an explicit window owned by the supplied process (the caller by default).
    public init(windowID: CGWindowID, processID: Int32 = ProcessInfo.processInfo.processIdentifier) {
        self.windowID = windowID
        self.processID = processID
    }

    /// Whether the process currently has screen-capture access; does not request it.
    public static var isAuthorized: Bool { CGPreflightScreenCaptureAccess() }

    /// Captures one native SDR window image without cursor or shadow.
    /// Selection is refreshed per call. Errors propagate without hierarchy or desktop fallback.
    public func capture() async throws -> CapturedImage {
        try Task.checkCancellation()
        guard Self.isAuthorized else { throw CaptureError.permissionRequired }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        try Task.checkCancellation()
        guard let window = content.windows.first(where: {
            $0.windowID == windowID && $0.owningApplication?.processID == processID
        }) else { throw CaptureError.windowUnavailable }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = Double(filter.pointPixelScale)
        let width = Double(filter.contentRect.width) * scale
        let height = Double(filter.contentRect.height) * scale
        guard scale.isFinite, scale > 0, width.isFinite, height.isFinite,
              width > 0, height > 0, width < Double(Int.max), height < Double(Int.max),
              abs(width - width.rounded()) < 0.001,
              abs(height - height.rounded()) < 0.001 else { throw CaptureError.invalidGeometry }
        let configuration = SCStreamConfiguration()
        configuration.width = Int(width.rounded())
        configuration.height = Int(height.rounded())
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        try Task.checkCancellation()
        guard image.width == configuration.width, image.height == configuration.height else {
            throw CaptureError.unexpectedDimensions
        }
        return try CapturedImage(cgImage: image, scale: scale)
    }

    /// Captures and stores a frame through the same recorder used by custom sources.
    /// Backend and window provenance take precedence over caller metadata.
    @discardableResult
    public func record(
        to screener: Screener, reason: String, metadata: [String: String] = [:]
    ) async throws -> CapturedImage {
        let image = try await capture()
        let fields = metadata.merging([
            "capture.backend": "ScreenCaptureKit.window",
            "capture.windowID": String(windowID),
            "capture.processID": String(processID),
        ]) { _, actual in actual }
        try await screener.recordFrame(image, reason: reason, metadata: fields)
        return image
    }
}
#endif
