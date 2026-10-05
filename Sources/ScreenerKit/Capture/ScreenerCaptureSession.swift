/// Connects a main-actor platform renderer to the background trace writer.
@MainActor
public struct ScreenerCaptureSession {
    private let screener: Screener

    public init(screener: Screener) {
        self.screener = screener
    }

    public func capture(from source: any ScreenerCaptureSource, reason: String) async throws {
        let image = try source.capture()
        try await screener.recordFrame(image, reason: reason)
    }
}
