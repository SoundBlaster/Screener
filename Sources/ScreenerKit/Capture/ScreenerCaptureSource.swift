/// A platform renderer that supplies one image from the UI actor.
@MainActor
public protocol ScreenerCaptureSource {
    /// Renders the current state or throws when an image cannot be produced.
    func capture() throws -> CapturedImage
}
