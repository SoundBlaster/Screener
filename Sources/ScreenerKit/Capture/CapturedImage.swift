import CoreGraphics

/// An immutable pixel image paired with its pixels-per-point display scale.
public struct CapturedImage: Sendable {
    public let cgImage: CGImage
    public let scale: Double

    /// Validates positive image dimensions and a finite, positive display scale.
    public init(cgImage: CGImage, scale: Double) throws {
        guard cgImage.width > 0, cgImage.height > 0, scale.isFinite, scale > 0 else {
            throw ScreenerCaptureError.invalidImage
        }
        self.cgImage = cgImage
        self.scale = scale
    }
}
