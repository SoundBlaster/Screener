import Foundation
import Testing
import CoreGraphics
import ImageIO
import ScreenerCore
@testable import ScreenerKit

#if canImport(AppKit)
import AppKit
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif

@Suite("Screener session lifecycle")
struct ScreenerTests {
    @Test func recordsMarkersAndClosesSession() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let screener = Screener()
        let bundle = try await screener.startSession(
            name: "login-flow",
            appBundleID: "dev.example.app",
            tracesDirectory: root
        )
        try await screener.mark("Login.submitted", metadata: ["method": "passkey"])
        try await screener.stopSession()

        let records = try TraceBundleReader(url: bundle).timeline()
        #expect(records.map(\.kind) == [.sessionStarted, .marker, .sessionEnded])
        #expect(records[1].name == "Login.submitted")
        #expect(records[1].metadata["method"] == "passkey")
    }

    @Test func rejectsInvalidLifecycleTransitions() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let screener = Screener()
        _ = try await screener.startSession(
            name: "first", appBundleID: "dev.example.app", tracesDirectory: root
        )

        do {
            _ = try await screener.startSession(
                name: "second", appBundleID: "dev.example.app", tracesDirectory: root
            )
            Issue.record("Expected starting a second active session to fail")
        } catch let error as ScreenerError {
            #expect(error == .sessionAlreadyActive)
        }

        try await screener.stopSession()
        do {
            try await screener.stopSession()
            Issue.record("Expected stopping without an active session to fail")
        } catch let error as ScreenerError {
            #expect(error == .noActiveSession)
        }
    }

    @MainActor
    @Test func captureSessionWritesPNGAndKeyframeRecord() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let screener = Screener()
        let bundle = try await screener.startSession(
            name: "capture-test", appBundleID: "dev.example.app", tracesDirectory: root
        )
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(
            data: nil, width: 20, height: 12, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: 0.9, green: 0.2, blue: 0.1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 20, height: 12))
        let cgImage = try #require(context.makeImage())
        let captured = try CapturedImage(cgImage: cgImage, scale: 2)
        let captureSession = ScreenerCaptureSession(screener: screener)
        try await captureSession.capture(from: FixedCaptureSource(image: captured), reason: "fixture-state")
        try await screener.recordFrame(captured, reason: "stream-frame", metadata: [
            "capture.backend": "ScreenCaptureKit", "capture.presentationSeconds": "12.5",
            "pixelWidth": "999", "scale": "999", "encoding": "invalid"
        ])
        try await screener.stopSession()

        let frames = try TraceBundleReader(url: bundle).timeline().filter { $0.kind == .keyframe }
        let streamFrame = try #require(frames.last)
        #expect(streamFrame.metadata["capture.backend"] == "ScreenCaptureKit")
        #expect(streamFrame.metadata["capture.presentationSeconds"] == "12.5")
        #expect(streamFrame.metadata["pixelWidth"] == "20")
        #expect(streamFrame.metadata["scale"] == "2.0")
        #expect(streamFrame.metadata["encoding"] == "png")
        let frame = try #require(frames.first)
        #expect(frame.name == "fixture-state")
        #expect(frame.metadata["pixelWidth"] == "20")
        #expect(frame.metadata["pixelHeight"] == "12")
        #expect(frame.metadata["scale"] == "2.0")
        let blob = try #require(frame.blob)
        let pngData = try Data(contentsOf: bundle.appending(path: blob))
        let imageSource = try #require(CGImageSourceCreateWithData(pngData as CFData, nil))
        let decodedImage = try #require(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
        #expect(decodedImage.width == 20)
        #expect(decodedImage.height == 12)
    }

    @Test func frameFinishesBeforeLaterMarkerAndSessionEndAfterEncoding() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let encoder = ControlledPNGEncoder()
        let screener = Screener(imageEncoder: encoder)
        let bundle = try await screener.startSession(
            name: "ordered-capture", appBundleID: "dev.example.app", tracesDirectory: root
        )
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = try #require(context.makeImage())
        let captured = try CapturedImage(cgImage: image, scale: 1)

        let frameTask = Task { try await screener.recordFrame(captured, reason: "captured-first") }
        await encoder.waitUntilEncoding()
        await encoder.resumeEncoding()
        try await frameTask.value
        try await screener.mark("marker-after-capture")
        try await screener.stopSession()

        let records = try TraceBundleReader(url: bundle).timeline()
        #expect(records.map(\.kind) == [.sessionStarted, .keyframe, .marker, .sessionEnded])
        #expect(records[1].name == "captured-first")
        #expect(records[2].name == "marker-after-capture")
        #expect(records[1].timestamp <= records[2].timestamp)
        #expect(records[1].monotonicNanoseconds <= records[2].monotonicNanoseconds)
    }

    #if canImport(AppKit)
    @MainActor
    @Test func appKitCaptureRendersViewHierarchy() throws {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 60))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.systemRed.cgColor
        let captured = try AppKitCaptureSource(view: root).capture()

        #expect(captured.cgImage.width > 0)
        #expect(captured.cgImage.height > 0)
        #expect(Double(captured.cgImage.width) / 100 == captured.scale)
        #expect(Double(captured.cgImage.height) / 60 == captured.scale)
    }

    @MainActor
    @Test func appKitCaptureFillsTransparentPixelsWithWindowBackground() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 60),
                              styleMask: .borderless, backing: .buffered, defer: true)
        window.backgroundColor = NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 60))
        let left = NSView(frame: NSRect(x: 0, y: 0, width: 50, height: 60))
        left.wantsLayer = true
        left.layer?.backgroundColor = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1).cgColor
        content.addSubview(left)
        window.contentView = content

        let flattened = try AppKitCaptureSource(view: content).capture().cgImage
        let leftPixel = try #require(rgba(of: flattened, atFractionX: 0.25))
        let rightPixel = try #require(rgba(of: flattened, atFractionX: 0.75))
        #expect(leftPixel.red > 200 && leftPixel.blue < 60 && leftPixel.alpha == 255)
        #expect(rightPixel.blue > 200 && rightPixel.red < 60 && rightPixel.alpha == 255)

        let transparent = try AppKitCaptureSource(view: content, background: .transparent).capture().cgImage
        let clearPixel = try #require(rgba(of: transparent, atFractionX: 0.75))
        #expect(clearPixel.alpha == 0)
    }

    @MainActor
    @Test func appKitCaptureKeepsSubviewTransparencyByDefault() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 60),
                              styleMask: .borderless, backing: .buffered, defer: true)
        window.backgroundColor = NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 60))
        let child = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 60))
        let left = NSView(frame: NSRect(x: 0, y: 0, width: 50, height: 60))
        left.wantsLayer = true
        left.layer?.backgroundColor = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1).cgColor
        child.addSubview(left)
        content.addSubview(child)
        window.contentView = content

        // On screen a subview's clear pixels show its ancestors, not the window color.
        let automatic = try AppKitCaptureSource(view: child).capture().cgImage
        #expect(try #require(rgba(of: automatic, atFractionX: 0.75)).alpha == 0)
        #expect(try #require(rgba(of: automatic, atFractionX: 0.25)).red > 200)

        let forced = try AppKitCaptureSource(view: child, background: .window).capture().cgImage
        #expect(try #require(rgba(of: forced, atFractionX: 0.75)).blue > 200)
    }

    @Test func compositeKeepsOpaquePixelsAndFillsClearOnes() throws {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: 4, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        let image = try #require(context.makeImage())

        let flattened = try #require(AppKitCaptureSource.composite(
            image, over: CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)))
        let left = try #require(rgba(of: flattened, atFractionX: 0.25))
        let right = try #require(rgba(of: flattened, atFractionX: 0.75))
        #expect(left.red == 255 && left.green == 0 && left.alpha == 255)
        #expect(right.green == 255 && right.red == 0 && right.alpha == 255)
    }
    #endif

    #if canImport(SwiftUI)
    @MainActor
    @Test func swiftUICaptureHonorsLayoutAndScale() throws {
        let source = SwiftUICaptureSource(
            content: Rectangle().fill(.orange).frame(width: 48, height: 32),
            scale: 2
        )
        let captured = try source.capture()

        #expect(captured.cgImage.width == 96)
        #expect(captured.cgImage.height == 64)
    }
    #endif
}

/// Reads one sRGB pixel from the vertical middle of `image`, `fraction` of the way across.
private func rgba(of image: CGImage, atFractionX fraction: Double)
    -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)? {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
              data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
              bytesPerRow: image.width * 4, space: space,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    guard let data = context.data else { return nil }
    let x = min(image.width - 1, Int(Double(image.width) * fraction))
    let offset = (image.height / 2) * image.width * 4 + x * 4
    let bytes = data.assumingMemoryBound(to: UInt8.self)
    return (bytes[offset], bytes[offset + 1], bytes[offset + 2], bytes[offset + 3])
}

@MainActor
private struct FixedCaptureSource: ScreenerCaptureSource {
    let image: CapturedImage
    func capture() throws -> CapturedImage { image }
}

private actor ControlledPNGEncoder: PNGImageEncoding {
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var encodingContinuation: CheckedContinuation<Void, Never>?

    func encodePNG(_ image: CGImage) async throws -> Data {
        started = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        await withCheckedContinuation { encodingContinuation = $0 }
        return Data([0x89, 0x50, 0x4E, 0x47])
    }

    func waitUntilEncoding() async {
        guard !started else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func resumeEncoding() {
        encodingContinuation?.resume()
        encodingContinuation = nil
    }
}
