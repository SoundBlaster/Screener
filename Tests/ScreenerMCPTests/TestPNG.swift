import CoreGraphics
import Foundation
import ImageIO

func makeTestPNG(width: Int = 12, height: Int = 8, red: CGFloat = 0.2) throws -> Data {
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw TestPNGError.cannotCreateImage
    }
    context.setFillColor(CGColor(red: red, green: 0.4, blue: 0.7, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    guard let image = context.makeImage() else { throw TestPNGError.cannotCreateImage }
    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else {
        throw TestPNGError.cannotEncodeImage
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw TestPNGError.cannotEncodeImage }
    return output as Data
}

private enum TestPNGError: Error {
    case cannotCreateImage
    case cannotEncodeImage
}
