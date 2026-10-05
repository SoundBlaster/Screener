#if canImport(AppKit)
import AppKit

@MainActor
public struct AppKitCaptureSource: ScreenerCaptureSource {
    private let view: NSView

    public init(view: NSView) {
        self.view = view
    }

    public func capture() throws -> CapturedImage {
        let bounds = view.bounds
        guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else {
            throw ScreenerCaptureError.emptyBounds
        }
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: bounds) else {
            throw ScreenerCaptureError.imageUnavailable
        }

        view.cacheDisplay(in: bounds, to: bitmap)
        guard let cgImage = bitmap.cgImage else { throw ScreenerCaptureError.imageUnavailable }
        let scale = Double(bitmap.pixelsWide) / Double(bounds.width)
        return try CapturedImage(cgImage: cgImage, scale: scale)
    }
}
#endif
