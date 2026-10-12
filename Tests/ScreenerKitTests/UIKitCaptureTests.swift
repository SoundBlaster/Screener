#if canImport(UIKit)
import UIKit
import Testing
@testable import ScreenerKit

@MainActor
@Suite("UIKit capture")
struct UIKitCaptureTests {
    @Test func windowCaptureUsesDisplayScale() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 80, height: 60)
        window.rootViewController = UIViewController()
        window.backgroundColor = .red
        window.isHidden = false
        defer { window.isHidden = true }
        window.layoutIfNeeded()
        let expectedScale = window.traitCollection.displayScale
        #expect(expectedScale > 0)

        let image = try UIKitCaptureSource(view: window).capture()
        #expect(image.scale == Double(expectedScale))
        #expect(image.cgImage.width == Int(80 * expectedScale))
        #expect(image.cgImage.height == Int(60 * expectedScale))
    }

    @available(iOS 17, *)
    @Test(arguments: [CGFloat(1), 2, 3])
    func captureUsesCurrentViewTraits(scale: CGFloat) throws {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 40, height: 24))
        view.backgroundColor = .blue
        view.traitOverrides.displayScale = scale
        view.updateTraitsIfNeeded()
        let source = UIKitCaptureSource(view: view)
        let image = try source.capture()
        #expect(image.scale == Double(scale))
        #expect(image.cgImage.width == Int(40 * scale))
        #expect(image.cgImage.height == Int(24 * scale))

        view.traitOverrides.displayScale = 2
        view.updateTraitsIfNeeded()
        let updated = try source.capture()
        #expect(updated.scale == 2)
        #expect(updated.cgImage.width == 80)
    }

    @Test func uiImageWithoutBitmapBackingIsRasterized() throws {
        // A real symbol may expose lazy CG backing on newer OS releases.
        // This drawable UIImage fixture exercises the missing-backing boundary deterministically.
        let symbol = DrawingOnlyImage()
        try #require(symbol.cgImage == nil)
        try #require(symbol.ciImage == nil)
        let image = try CapturedImage(uiImage: symbol)
        #expect(image.scale == Double(symbol.scale))
        #expect(image.cgImage.width == Int(ceil(symbol.size.width * symbol.scale)))
        #expect(image.cgImage.height == Int(ceil(symbol.size.height * symbol.scale)))
        let context = try #require(CGContext(data: nil, width: image.cgImage.width,
            height: image.cgImage.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image.cgImage, in: CGRect(x: 0, y: 0,
            width: image.cgImage.width, height: image.cgImage.height))
        let data = try #require(context.data)
        let bytes = data.bindMemory(to: UInt8.self, capacity: context.bytesPerRow * context.height)
        let hasVisiblePixels = (0..<context.height).contains { y in
            (0..<context.width).contains { x in bytes[y * context.bytesPerRow + x * 4 + 3] > 0 }
        }
        #expect(hasVisiblePixels)
    }

    @Test func systemSymbolUIImageCanBeCaptured() throws {
        let source = try #require(UIImage(systemName: "star.fill"))
        let image = try CapturedImage(uiImage: source)
        #expect(image.scale == Double(source.scale))
        #expect(image.cgImage.width > 0)
        #expect(image.cgImage.height > 0)
    }

    @Test func bitmapUIImageKeepsScaleAndAppliesOrientationOnce() throws {
        let context = try #require(CGContext(data: nil, width: 12, height: 8,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(UIColor.red.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 12, height: 8))
        let bitmap = try #require(context.makeImage())
        let source = UIImage(cgImage: bitmap, scale: 2, orientation: .right)
        let image = try CapturedImage(uiImage: source)
        #expect(image.scale == 2)
        #expect(image.cgImage.width == 8)
        #expect(image.cgImage.height == 12)
    }

    @Test func emptyUIImageFailsWithoutStartingRenderer() {
        #expect(throws: ScreenerCaptureError.invalidImage) {
            try CapturedImage(uiImage: UIImage())
        }
    }

    @Test func emptyViewFailsCapture() {
        #expect(throws: ScreenerCaptureError.emptyBounds) {
            try UIKitCaptureSource(view: UIView(frame: .zero)).capture()
        }
    }
}

// UIKit's input boundary is concrete UIImage. This draw-only fixture has no mutable
// state and inherits UIImage's sendability; tests invoke drawing on MainActor only.
private final class DrawingOnlyImage: UIImage, @unchecked Sendable {
    override var cgImage: CGImage? { nil }
    override var ciImage: CIImage? { nil }
    override var size: CGSize { CGSize(width: 40, height: 24) }
    override var scale: CGFloat { 2 }

    override func draw(in rect: CGRect) {
        UIColor.red.setFill()
        UIRectFill(rect)
    }
}
#if canImport(ScreenCaptureKit) && !targetEnvironment(simulator) && !targetEnvironment(macCatalyst)
@MainActor
@Suite("ScreenCaptureKit session lifecycle without permission")
struct ScreenCaptureKitLifecycleTests {
    @Test func stoppingBeforeStartIsTerminalAndIdempotent() async {
        guard #available(iOS 27, *) else { return }
        let session = ScreenCaptureKitSession(screener: Screener())
        await session.stop()
        await session.stop()
        #expect(session.state == .finished)
        #expect(session.failure == nil)
        await #expect(throws: ScreenCaptureKitSession.SessionError.alreadyStarted) {
            try await session.start()
        }
    }

    @Test func absentTraceFailsBeforePermissionRequest() async {
        guard #available(iOS 27, *) else { return }
        let session = ScreenCaptureKitSession(screener: Screener())
        await #expect(throws: ScreenerError.noActiveSession) {
            try await session.start()
        }
        #expect(session.state == .finished)
        #expect(session.failure as? ScreenerError == .noActiveSession)
        await session.stop()
    }
}
#endif

#endif
