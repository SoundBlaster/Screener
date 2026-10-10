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

    @Test func emptyViewFailsCapture() {
        #expect(throws: ScreenerCaptureError.emptyBounds) {
            try UIKitCaptureSource(view: UIView(frame: .zero)).capture()
        }
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
