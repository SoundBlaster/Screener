#if canImport(ScreenCaptureKit) && !targetEnvironment(simulator) && !targetEnvironment(macCatalyst)
import UIKit
import ScreenerKit

/// Exercises the SDK API rather than the independent PNG research sink.
@available(iOS 27, *)
@MainActor
final class ScreenTraceFixture {
    private let recorder = Screener()
    private var session: ScreenCaptureKitSession?
    private var task: Task<Void, Never>?
    private var finishing = false
    private let root = URL.documentsDirectory.appending(path: "ScreenCaptureTraces", directoryHint: .isDirectory)
    private let status = UILabel(frame: CGRect(x: 24, y: 664, width: 340, height: 44))

    init(window: UIWindow) {
        status.text = "picking"
        status.accessibilityIdentifier = "fixture.captureStatus"
        status.textColor = .black
        status.backgroundColor = .white
        window.rootViewController?.view.addSubview(status)
        let stop = UIButton(type: .system)
        stop.configuration = .borderedProminent()
        stop.setTitle("Stop capture", for: .normal)
        stop.accessibilityIdentifier = "fixture.stopCapture"
        stop.frame = CGRect(x: 24, y: 610, width: 200, height: 44)
        stop.addAction(UIAction { [weak self] _ in Task { await self?.finish() } }, for: .touchUpInside)
        window.rootViewController?.view.addSubview(stop)
    }

    func present() {
        task = Task {
            do {
                let url = try await recorder.startSession(name: "screen-capture-sdk",
                    appBundleID: "dev.screener.UIKitFixture", tracesDirectory: root)
                try url.lastPathComponent.write(to: root.appending(path: "latest-run.txt"), atomically: true, encoding: .utf8)
                let capture = ScreenCaptureKitSession(screener: recorder)
                session = capture
                try await capture.start()
                guard !finishing else { return }
                status.text = "running"
                while capture.state != .finished {
                    try await Task.sleep(for: .milliseconds(250))
                }
                await finish()
            } catch {
                writeError(error)
                await finish()
            }
        }
    }

    private func finish() async {
        guard !finishing else { return }
        finishing = true
        await session?.stop()
        if let error = session?.failure { writeError(error) }
        do { try await recorder.stopSession() } catch { writeError(error) }
        status.text = "finished"
    }

    private func writeError(_ error: any Error) {
        print("ScreenTraceFixture: \(error)")
        try? String(describing: error).write(to: root.appending(path: "error.txt"), atomically: true, encoding: .utf8)
    }
}
#endif
