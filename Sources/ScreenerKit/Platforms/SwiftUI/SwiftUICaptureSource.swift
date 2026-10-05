#if canImport(SwiftUI)
import SwiftUI

/// Renders an explicit SwiftUI subtree. Capture a hosting NSView/UIView for full-window state.
@MainActor
public struct SwiftUICaptureSource<Content: View>: ScreenerCaptureSource {
    private let content: Content
    private let size: CGSize?
    private let scale: CGFloat

    public init(content: Content, size: CGSize? = nil, scale: CGFloat = 1) {
        self.content = content
        self.size = size
        self.scale = scale
    }

    public func capture() throws -> CapturedImage {
        guard scale.isFinite, scale > 0,
              size.map({ $0.width.isFinite && $0.height.isFinite && $0.width > 0 && $0.height > 0 }) ?? true else {
            throw ScreenerCaptureError.emptyBounds
        }

        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        if let size {
            renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
        }
        guard let cgImage = renderer.cgImage else { throw ScreenerCaptureError.imageUnavailable }
        return try CapturedImage(cgImage: cgImage, scale: Double(scale))
    }
}
#endif
