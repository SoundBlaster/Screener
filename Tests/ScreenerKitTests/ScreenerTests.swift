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
        try await screener.stopSession()

        let frame = try #require(TraceBundleReader(url: bundle).timeline().first { $0.kind == .keyframe })
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

    @Test func frameFinishesBeforeLaterMarkerAndSessionEndDuringEncoding() async throws {
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
        let markerTask = Task { try await screener.mark("marker-after-capture") }
        let stopTask = Task { try await screener.stopSession() }
        await encoder.resumeEncoding()

        try await frameTask.value
        try await markerTask.value
        try await stopTask.value

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
