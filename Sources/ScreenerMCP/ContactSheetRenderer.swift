import CoreGraphics
import CoreText
import Foundation
import ImageIO

enum ContactSheetRenderer {
    private static let cellWidth = 260
    private static let cellHeight = 210
    private static let gap = 16
    private static let imageHeight = 156

    static func render(_ frames: [(TraceContactSheetCell, Data)], columns: Int) throws -> Data {
        let columnCount = max(1, columns)
        let rowCount = max(1, (frames.count + columnCount - 1) / columnCount)
        let width = columnCount * cellWidth + (columnCount + 1) * gap
        let height = rowCount * cellHeight + (rowCount + 1) * gap
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw TraceCatalogError.invalidFrameImage
        }

        context.setFillColor(CGColor(red: 0.94, green: 0.95, blue: 0.97, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        for (position, frame) in frames.enumerated() {
            guard let source = CGImageSourceCreateWithData(frame.1 as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw TraceCatalogError.invalidFrameImage
            }

            let column = position % columnCount
            let row = position / columnCount
            let x = gap + column * (cellWidth + gap)
            let y = height - gap - (row + 1) * cellHeight - row * gap
            let cellRect = CGRect(x: x, y: y, width: cellWidth, height: cellHeight)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(cellRect)
            context.setStrokeColor(CGColor(gray: 0.84, alpha: 1))
            context.setLineWidth(1)
            context.stroke(cellRect)

            let imageBounds = CGRect(x: x + 12, y: y + 42, width: cellWidth - 24, height: imageHeight)
            context.draw(image, in: aspectFit(image, within: imageBounds))
            drawCaption(for: frame.0, in: context, x: x + 12, y: y + 16)
        }

        guard let renderedImage = context.makeImage() else { throw TraceCatalogError.invalidFrameImage }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else {
            throw TraceCatalogError.invalidFrameImage
        }
        CGImageDestinationAddImage(destination, renderedImage, nil)
        guard CGImageDestinationFinalize(destination) else { throw TraceCatalogError.invalidFrameImage }
        return output as Data
    }

    private static func aspectFit(_ image: CGImage, within bounds: CGRect) -> CGRect {
        let widthScale = bounds.width / CGFloat(image.width)
        let heightScale = bounds.height / CGFloat(image.height)
        let scale = min(widthScale, heightScale)
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private static func drawCaption(for cell: TraceContactSheetCell, in context: CGContext, x: Int, y: Int) {
        let name = cell.name.count > 27 ? String(cell.name.prefix(26)) + "…" : cell.name
        let caption = "\(cell.index).  \(name)"
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 13, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.18, alpha: 1),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: caption, attributes: attributes))
        context.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, context)
    }
}
