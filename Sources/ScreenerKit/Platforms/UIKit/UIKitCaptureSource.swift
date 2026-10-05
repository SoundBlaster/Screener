#if canImport(UIKit)
import UIKit

@MainActor
public struct UIKitCaptureSource: ScreenerCaptureSource {
    private let view: UIView
    private let afterScreenUpdates: Bool

    public init(view: UIView, afterScreenUpdates: Bool = true) {
        self.view = view
        self.afterScreenUpdates = afterScreenUpdates
    }

    public func capture() throws -> CapturedImage {
        let bounds = view.bounds
        guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else {
            throw ScreenerCaptureError.emptyBounds
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = view.window?.screen.scale ?? 1
        format.opaque = view.isOpaque
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: format)
        var renderedHierarchy = false
        let image = renderer.image { _ in
            renderedHierarchy = view.drawHierarchy(in: bounds, afterScreenUpdates: afterScreenUpdates)
        }
        guard renderedHierarchy, let cgImage = image.cgImage else {
            throw ScreenerCaptureError.incompleteHierarchy
        }
        return try CapturedImage(cgImage: cgImage, scale: Double(format.scale))
    }
}
#endif
