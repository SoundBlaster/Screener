import Foundation

/// An immutable image and optional producer time, independent of recorder time.
public struct CapturedFrame: Sendable {
    /// The image to encode and store.
    public let image: CapturedImage
    /// Source presentation time in its own clock domain; never used to reorder the trace.
    public let presentationSeconds: Double?

    /// Creates a frame with an optional finite source timestamp.
    public init(image: CapturedImage, presentationSeconds: Double? = nil) throws {
        guard presentationSeconds?.isFinite != false else {
            throw CapturedImageConversionError.invalidPresentationTime
        }
        self.image = image
        self.presentationSeconds = presentationSeconds
    }
}
