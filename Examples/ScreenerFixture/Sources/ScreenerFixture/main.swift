import AppKit
import ScreenerKit
import SwiftUI

@main
struct ScreenerFixtureApp: App {
    var body: some Scene {
        WindowGroup("Screener Fixture") {
            FixtureView()
        }
        .defaultSize(width: 640, height: 480)
    }
}

@MainActor
private final class FixtureModel: ObservableObject {
    let screener = Screener()
    @Published var window: NSWindow?
    @Published var phaseIndex = 0
    @Published var status = "Start a session to record this fixture."
    @Published var bundleURL: URL?
    @Published var isRecording = false

    private let phases = ["Idle", "Loading profile", "Profile loaded"]
    private lazy var captureSession = ScreenerCaptureSession(screener: screener)

    var phaseName: String { phases[phaseIndex] }

    func start() async {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let directory = caches.appending(path: "ScreenerFixture/Traces")
        do {
            bundleURL = try await screener.startSession(
                name: "fixture-session",
                appBundleID: Bundle.main.bundleIdentifier ?? "dev.screener.fixture",
                tracesDirectory: directory
            )
            isRecording = true
            status = "Recording session started."
        } catch {
            status = "Start failed: \(error.localizedDescription)"
        }
    }

    func advance() async {
        phaseIndex = (phaseIndex + 1) % phases.count
        guard isRecording else {
            status = "Fixture advanced to \(phaseName). Start a session to record it."
            return
        }
        do {
            try await screener.mark("Fixture.phase.changed", metadata: ["phase": phaseName])
            status = "Recorded marker for \(phaseName)."
        } catch {
            status = "Marker failed: \(error.localizedDescription)"
        }
    }

    func capture() async {
        guard let contentView = window?.contentView else {
            status = "Window content is not available yet."
            return
        }
        do {
            try await captureSession.capture(
                from: AppKitCaptureSource(view: contentView),
                reason: "Fixture.capture.\(phaseName)"
            )
            status = "Captured a PNG keyframe for \(phaseName)."
        } catch {
            status = "Capture failed: \(error.localizedDescription)"
        }
    }

    func stop() async {
        do {
            try await screener.stopSession()
            isRecording = false
            status = "Session written to \(bundleURL?.path ?? "the cache directory")."
        } catch {
            status = "Stop failed: \(error.localizedDescription)"
        }
    }
}

@MainActor
private struct FixtureView: View {
    @StateObject private var model = FixtureModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Screener Fixture").font(.title2.bold())
                    Text("Exercise transient UI states and record native frames.")
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(model.phaseName).font(.title.bold())
                Text(description)
                    .foregroundStyle(.secondary)
                ProgressView(value: Double(model.phaseIndex + 1), total: 3)
                    .tint(model.phaseIndex == 2 ? .green : .blue)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
            .animation(.easeInOut(duration: 0.25), value: model.phaseIndex)

            HStack {
                Button("Advance state") { Task { await model.advance() } }
                Spacer()
                Button("Start recording") { Task { await model.start() } }
                    .disabled(model.isRecording)
                Button("Capture frame") { Task { await model.capture() } }
                    .disabled(!model.isRecording)
                Button("Stop") { Task { await model.stop() } }
                    .disabled(!model.isRecording)
            }

            Text(model.status)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            if let bundleURL = model.bundleURL {
                Text(bundleURL.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
            Text("This fixture records only when you start a local session.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(minWidth: 600, minHeight: 420)
        .background(WindowProbe { model.window = $0 }.frame(width: 1, height: 1).opacity(0))
    }

    private var description: String {
        switch model.phaseIndex {
        case 0: "A stable starting state, ready for a transition."
        case 1: "A delayed state that can be marked and captured."
        default: "The loaded state after the simulated transition."
        }
    }
}

@MainActor
private struct WindowProbe: NSViewRepresentable {
    let onWindowChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> WindowProbeView {
        let view = WindowProbeView()
        view.onWindowChange = onWindowChange
        return view
    }

    func updateNSView(_ nsView: WindowProbeView, context: Context) {
        nsView.onWindowChange = onWindowChange
        onWindowChange(nsView.window)
    }
}

@MainActor
private final class WindowProbeView: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }
}
