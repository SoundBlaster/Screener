#if canImport(UIKit)
import UIKit

/// Renders a UIKit hierarchy at its current display scale.
/// Pass the containing UIWindow when capturing visual effects. Hierarchy rendering
/// is not a system-compositor screenshot and may differ for blur or glass materials.
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
        // UIWindow.window can be nil. Read the local traits instead of falling
        // back to 1x for the very window whose hierarchy we are capturing.
        let displayScale = view.traitCollection.displayScale
        if displayScale.isFinite, displayScale > 0 {
            format.scale = displayScale
        }
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
