#if canImport(CoreVideo) && canImport(CoreMedia)
import CoreGraphics
import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import ImageIO

extension CapturedImage {
    /// Copies an SDR BGRA8 or RGBA8 pixel buffer while holding a read lock.
    /// The caller must prevent concurrent producer writes during this synchronous copy.
    /// The buffer may be reused after return. Planar/YUV and HDR formats are rejected.
    public init(
        pixelBuffer: CVPixelBuffer, colorSpace: CGColorSpace,
        orientation: CGImagePropertyOrientation = .up,
        premultipliedAlpha: Bool = true, scale: Double
    ) throws {
        let code = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let format: PixelFormat
        switch code {
        case kCVPixelFormatType_32BGRA: format = .bgra8
        case kCVPixelFormatType_32RGBA: format = .rgba8
        default: throw CapturedImageConversionError.unsupportedPixelFormat(code)
        }
        guard !CVPixelBufferIsPlanar(pixelBuffer),
              CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess else {
            throw CapturedImageConversionError.invalidBuffer
        }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard height > 0, stride > 0, stride <= Int.max / height,
              stride * height <= CVPixelBufferGetDataSize(pixelBuffer),
              let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw CapturedImageConversionError.invalidBuffer
        }
        let snapshot = try CapturedImage(pixels: Data(bytes: base, count: stride * height),
            width: CVPixelBufferGetWidth(pixelBuffer), height: height, bytesPerRow: stride,
            format: format, colorSpace: colorSpace, premultipliedAlpha: premultipliedAlpha, scale: scale)
        if orientation == .up {
            self = snapshot
        } else {
            try self.init(ciImage: CIImage(cgImage: snapshot.cgImage), colorSpace: colorSpace,
                orientation: orientation, scale: scale)
        }
    }
}

extension CapturedFrame {
    /// Copies a complete image-bearing sample and preserves its valid numeric source PTS.
    /// Color, orientation and alpha interpretation are supplied by the producer.
    public init(
        sampleBuffer: CMSampleBuffer, colorSpace: CGColorSpace,
        orientation: CGImagePropertyOrientation = .up,
        premultipliedAlpha: Bool = true, scale: Double
    ) throws {
        guard CMSampleBufferIsValid(sampleBuffer), CMSampleBufferDataIsReady(sampleBuffer),
              let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            throw CapturedImageConversionError.incompleteSample
        }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        try self.init(image: CapturedImage(pixelBuffer: pixels, colorSpace: colorSpace,
            orientation: orientation, premultipliedAlpha: premultipliedAlpha, scale: scale),
            presentationSeconds: time.isNumeric ? CMTimeGetSeconds(time) : nil)
    }
}
#endif
