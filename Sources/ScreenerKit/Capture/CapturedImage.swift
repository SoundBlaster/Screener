import CoreGraphics

public struct CapturedImage: Sendable {
    public let cgImage: CGImage
    public let scale: Double

    public init(cgImage: CGImage, scale: Double) throws {
        guard cgImage.width > 0, cgImage.height > 0, scale.isFinite, scale > 0 else {
            throw ScreenerCaptureError.invalidImage
        }
        self.cgImage = cgImage
        self.scale = scale
    }
}
