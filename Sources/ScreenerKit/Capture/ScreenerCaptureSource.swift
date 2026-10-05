@MainActor
public protocol ScreenerCaptureSource {
    func capture() throws -> CapturedImage
}
