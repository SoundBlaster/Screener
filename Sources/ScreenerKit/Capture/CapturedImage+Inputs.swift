import CoreGraphics
import CoreImage
import Foundation
import ImageIO

/// Conversion failures before a frame reaches the recorder.
public enum CapturedImageConversionError: Error, Equatable {
    /// Geometry, stride or backing byte count is invalid.
    case invalidBuffer
    /// The input pixel format is not supported by this converter.
    case unsupportedPixelFormat(UInt32)
    /// The conversion requires an RGB color space.
    case invalidColorSpace
    /// The encoded image cannot be decoded.
    case decodingFailed
    /// The sample is invalid, incomplete or has no image buffer.
    case incompleteSample
    /// Encoded orientation metadata is outside the EXIF orientation range.
    case invalidOrientation
    /// Source presentation time is nonfinite.
    case invalidPresentationTime
}

extension CapturedImage {
    /// Supported four-channel, eight-bit raw pixel layouts.
    public enum PixelFormat: Sendable {
        /// Red, green, blue, alpha bytes.
        case rgba8
        /// Blue, green, red, alpha bytes.
        case bgra8
    }

    /// Copies raw pixels into an image with explicit color and alpha interpretation.
    /// The producer may reuse its bytes after this initializer returns.
    /// No resizing or implicit color-space selection is performed.
    public init(
        pixels: Data, width: Int, height: Int, bytesPerRow: Int,
        format: PixelFormat, colorSpace: CGColorSpace,
        premultipliedAlpha: Bool = true, scale: Double
    ) throws {
        guard width > 0, height > 0, width <= Int.max / 4,
              bytesPerRow >= width * 4, bytesPerRow <= Int.max / height,
              pixels.count >= bytesPerRow * height else {
            throw CapturedImageConversionError.invalidBuffer
        }
        guard colorSpace.model == .rgb else { throw CapturedImageConversionError.invalidColorSpace }
        // Force an owned snapshot even when Data bridges a mutable external buffer.
        let owned = pixels.withUnsafeBytes { Data(bytes: $0.baseAddress!, count: bytesPerRow * height) }
        guard let provider = CGDataProvider(data: owned as CFData) else {
            throw ScreenerCaptureError.imageUnavailable
        }
        let alpha: CGImageAlphaInfo
        let order: CGBitmapInfo
        switch format {
        case .rgba8:
            alpha = premultipliedAlpha ? .premultipliedLast : .last
            order = .byteOrder32Big
        case .bgra8:
            alpha = premultipliedAlpha ? .premultipliedFirst : .first
            order = .byteOrder32Little
        }
        guard let image = CGImage(width: width, height: height, bitsPerComponent: 8,
            bitsPerPixel: 32, bytesPerRow: bytesPerRow, space: colorSpace,
            bitmapInfo: order.union(CGBitmapInfo(rawValue: alpha.rawValue)),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            throw ScreenerCaptureError.imageUnavailable
        }
        try self.init(cgImage: image, scale: scale)
    }

    /// Decodes the first encoded image and applies its EXIF orientation at native pixels.
    /// Decoding snapshots the supplied bytes; animated images contribute only their first frame.
    /// Non-up orientation is rasterized to SDR RGBA8; the up case retains decoded depth.
    public init(encodedImage: Data, scale: Double) throws {
        let owned = encodedImage.withUnsafeBytes { Data($0) }
        guard let source = CGImageSourceCreateWithData(owned as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0,
                [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else {
            throw CapturedImageConversionError.decodingFailed
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let value = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
        guard let orientation = CGImagePropertyOrientation(rawValue: value) else {
            throw CapturedImageConversionError.invalidOrientation
        }
        if orientation == .up {
            try self.init(cgImage: image, scale: scale)
        } else {
            guard let space = image.colorSpace, space.model == .rgb else {
                throw CapturedImageConversionError.invalidColorSpace
            }
            try self.init(ciImage: CIImage(cgImage: image), colorSpace: space,
                orientation: orientation, scale: scale)
        }
    }

    /// Rasterizes a finite, integral CIImage extent to owned RGBA8 pixels.
    /// Color conversion to the supplied RGB space and orientation are explicit.
    /// This SDR conversion does not preserve HDR/EDR or high-bit-depth samples.
    public init(
        ciImage: CIImage, colorSpace: CGColorSpace,
        orientation: CGImagePropertyOrientation = .up, scale: Double
    ) throws {
        guard colorSpace.model == .rgb else { throw CapturedImageConversionError.invalidColorSpace }
        let oriented = ciImage.oriented(orientation)
        let extent = oriented.extent
        guard !extent.isNull, !extent.isInfinite, extent.origin.x.isFinite,
              extent.origin.y.isFinite, extent.width.isFinite, extent.height.isFinite,
              extent.width > 0, extent.height > 0,
              extent == extent.integral else { throw CapturedImageConversionError.invalidBuffer }
        let context = CIContext(options: [.cacheIntermediates: false])
        guard let image = context.createCGImage(oriented, from: extent, format: .RGBA8, colorSpace: colorSpace) else {
            throw ScreenerCaptureError.imageUnavailable
        }
        try self.init(cgImage: image, scale: scale)
    }
}
