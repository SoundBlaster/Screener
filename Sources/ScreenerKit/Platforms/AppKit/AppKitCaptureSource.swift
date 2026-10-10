#if canImport(AppKit)
import AppKit

@MainActor
public struct AppKitCaptureSource: ScreenerCaptureSource {
    /// What fills pixels the view hierarchy leaves transparent.
    public enum Background: Sendable, Equatable {
        /// `.window` when the view is its window's content view, `.transparent` otherwise.
        /// A subview's transparent pixels show its ancestors on screen, not the window
        /// color, so only the content view can be completed with the window background.
        case automatic
        /// The window's background color, resolved in the view's appearance, so the frame
        /// matches the screen. A window's content view usually draws no background of its
        /// own: the window frame paints it, and `cacheDisplay` does not capture the frame.
        case window
        /// Keep transparent pixels transparent.
        case transparent
    }

    private let view: NSView
    private let background: Background

    public init(view: NSView, background: Background = .automatic) {
        self.view = view
        self.background = background
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
        guard let content = bitmap.cgImage else { throw ScreenerCaptureError.imageUnavailable }
        let scale = Double(bitmap.pixelsWide) / Double(bounds.width)
        guard fillsWithWindowBackground else { return try CapturedImage(cgImage: content, scale: scale) }
        guard let color = windowBackgroundColor(),
              let flattened = Self.composite(content, over: color) else {
            throw ScreenerCaptureError.imageUnavailable
        }
        return try CapturedImage(cgImage: flattened, scale: scale)
    }

    private var fillsWithWindowBackground: Bool {
        switch background {
        case .automatic: view.window.map { $0.contentView === view } ?? false
        case .window: true
        case .transparent: false
        }
    }

    /// Dynamic system colors resolve against the current drawing appearance, so resolve
    /// the window's color in the appearance the view actually draws with.
    private func windowBackgroundColor() -> CGColor? {
        let color = view.window?.backgroundColor ?? .windowBackgroundColor
        var resolved: CGColor?
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            // Pattern colors have no sRGB form; fall back to the system window color.
            resolved = (color.usingColorSpace(.sRGB) ?? NSColor.windowBackgroundColor.usingColorSpace(.sRGB))?.cgColor
        }
        return resolved
    }

    nonisolated static func composite(_ image: CGImage, over color: CGColor) -> CGImage? {
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(color)
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage()
    }
}
#endif
