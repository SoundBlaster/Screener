#if canImport(UIKit)
import UIKit
import CoreImage
import ImageIO

extension CapturedImage {
    /// Rasterizes a UIImage with its orientation and display scale to SDR sRGB pixels.
    @MainActor
    public init(uiImage: UIImage) throws {
        let orientation: CGImagePropertyOrientation
        switch uiImage.imageOrientation {
        case .up: orientation = .up
        case .down: orientation = .down
        case .left: orientation = .left
        case .right: orientation = .right
        case .upMirrored: orientation = .upMirrored
        case .downMirrored: orientation = .downMirrored
        case .leftMirrored: orientation = .leftMirrored
        case .rightMirrored: orientation = .rightMirrored
        @unknown default: throw ScreenerCaptureError.invalidImage
        }
        guard let source = uiImage.cgImage.map({ CIImage(cgImage: $0) }) ?? uiImage.ciImage else {
            throw ScreenerCaptureError.imageUnavailable
        }
        try self.init(ciImage: source, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            orientation: orientation, scale: Double(uiImage.scale))
    }
}
#endif

#if canImport(AppKit)
import AppKit

extension CapturedImage {
    /// Rasterizes an NSImage at explicitly requested pixels to SDR sRGB.
    /// The explicit pixel size also defines rasterization for vector representations.
    @MainActor
    public init(nsImage: NSImage, pixelWidth: Int, pixelHeight: Int, scale: Double) throws {
        guard pixelWidth > 0, pixelHeight > 0 else { throw ScreenerCaptureError.invalidImage }
        guard let context = CGContext(data: nil, width: pixelWidth, height: pixelHeight,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw ScreenerCaptureError.imageUnavailable
        }
        context.clear(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        nsImage.draw(in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight),
            from: .zero, operation: .copy, fraction: 1)
        guard let image = context.makeImage() else { throw ScreenerCaptureError.imageUnavailable }
        try self.init(cgImage: image, scale: scale)
    }
}
#endif
