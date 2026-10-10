/// Connects a main-actor platform renderer to the background trace writer.
@MainActor
public struct ScreenerCaptureSession {
    private let screener: Screener

    /// Connects captures to an existing recorder with an active session.
    public init(screener: Screener) {
        self.screener = screener
    }

    /// Renders on the main actor, then awaits PNG storage and timeline publication.
    /// This method captures one keyframe; it does not schedule repeated sampling.
    public func capture(from source: any ScreenerCaptureSource, reason: String) async throws {
        let image = try source.capture()
        try await screener.recordFrame(image, reason: reason)
    }
}
