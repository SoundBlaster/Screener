import Foundation
import ImageIO
import Testing
import MCP
import ScreenerKit
import ScreenerMCP

@MainActor
private final class FakeWindowProvider: WindowCaptureProvider {
    let window = RecordableWindow(windowID: 21, processID: 42, appBundleID: "dev.test.game", title: "Game")
    var captureCount = 0
    var available = true
    var permissionGranted = true
    var gate: CaptureGate?

    func windows(appBundleID: String) async throws -> [RecordableWindow] {
        guard permissionGranted else { throw WindowRecordingError.permissionRequired }
        return available && appBundleID == window.appBundleID ? [window] : []
    }

    func capture(windowID: UInt32, processID: Int32) async throws -> CapturedImage {
        captureCount += 1
        if let gate { await gate.block() }
        let source = try #require(CGImageSourceCreateWithData(makeTestPNG() as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return try CapturedImage(cgImage: image, scale: 1)
    }
}

private actor CaptureGate {
    private var started = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func block() async {
        started = true
        startWaiter?.resume()
        startWaiter = nil
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func release() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

@Suite("Window recording")
struct WindowRecordingTests {
    @Test func mcpRecordsOnlyRequestedCheckpointsAndExposesTrace() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let provider = FakeWindowProvider()
        let recording = WindowRecordingController(root: root, provider: provider)
        let catalog = TraceCatalog(roots: [root])
        let server = await ScreenerMCPServer.make(catalog: catalog, recording: recording)
        let transports = await InMemoryTransport.createConnectedPair()
        let client = Client(name: "window-test", version: "1")
        try await server.start(transport: transports.server)
        _ = try await client.connect(transport: transports.client)

        let tools = try await client.listTools().tools
        #expect(tools.count == 8)
        #expect(tools.first { $0.name == "screener.window_start" }?.annotations.readOnlyHint == false)
        let windowsRequest = try await client.send(CallTool.request(.init(name: "screener.windows", arguments: ["appBundleID": .string("dev.test.game")])))
        let windows = try await windowsRequest.value
        #expect(windows.structuredContent?.objectValue?["windows"]?.arrayValue?.count == 1)
        let startArgs: [String: MCP.Value] = ["appBundleID": .string("dev.test.game"), "windowID": .int(21), "processID": .int(42), "name": .string("Seam")]
        let invalid = try await client.callTool(name: "screener.window_start", arguments: startArgs.merging(["processID": .int(43)]) { _, value in value })
        #expect(invalid.isError == true)
        #expect(catalog.sessions().isEmpty)
        let startRequest = try await client.send(CallTool.request(.init(name: "screener.window_start", arguments: startArgs)))
        let start = try await startRequest.value
        #expect(start.isError != true)
        let rawID = try #require(start.structuredContent?.objectValue?["sessionID"]?.stringValue)
        let sessionID = try #require(UUID(uuidString: rawID))
        #expect(catalog.sessions().count == 1)
        #expect(try catalog.timeline(sessionID: sessionID).map(\.kind) == [.sessionStarted])
        #expect(await provider.captureCount == 0)
        let duplicate = try await client.callTool(name: "screener.window_start", arguments: startArgs)
        #expect(duplicate.isError == true)
        let wrong = try await client.callTool(name: "screener.window_capture", arguments: ["sessionID": .string(UUID().uuidString), "reason": .string("movement")])
        #expect(wrong.isError == true)
        let captureRequest = try await client.send(CallTool.request(.init(name: "screener.window_capture", arguments: ["sessionID": .string(rawID), "reason": .string("hero.moved")])))
        let captured = try await captureRequest.value
        #expect(captured.isError != true)
        #expect(captured.structuredContent?.objectValue?["capturedFrames"]?.intValue == 1)
        let stop = try await client.callTool(name: "screener.window_stop", arguments: ["sessionID": .string(rawID)])
        #expect(stop.isError != true)
        let records = try catalog.timeline(sessionID: sessionID)
        #expect(records.map(\.kind) == [.sessionStarted, .keyframe, .sessionEnded])
        #expect(records[1].name == "hero.moved")
        #expect(try catalog.frame(sessionID: sessionID, recordID: records[1].id).mimeType == "image/png")
        #expect(await provider.captureCount == 1)
        await server.stop()
        await client.disconnect()
    }

    @Test func disappearingWindowAndConcurrentStopFailWithoutLosingSession() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let provider = FakeWindowProvider()
        let recording = WindowRecordingController(root: root, provider: provider)
        let session = try await recording.start(appBundleID: "dev.test.game", windowID: 21, processID: 42, name: "Seam")
        await MainActor.run { provider.available = false }
        await #expect(throws: WindowRecordingError.windowUnavailable) {
            try await recording.capture(sessionID: session.sessionID, reason: "hidden")
        }
        await MainActor.run { provider.available = true }
        let gate = CaptureGate()
        await MainActor.run { provider.gate = gate }
        let task = Task { try await recording.capture(sessionID: session.sessionID, reason: "visible") }
        await gate.waitUntilStarted()
        await #expect(throws: WindowRecordingError.busy) { try await recording.stop(sessionID: session.sessionID) }
        await gate.release()
        #expect(try await task.value.capturedFrames == 1)
        _ = try await recording.stop(sessionID: session.sessionID)
        let records = try TraceCatalog(roots: [root]).timeline(sessionID: session.sessionID)
        #expect(records.map(\.kind) == [.sessionStarted, .keyframe, .sessionEnded])
    }

    @Test func missingPermissionDoesNotStartRecording() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let provider = FakeWindowProvider()
        await MainActor.run { provider.permissionGranted = false }
        let recording = WindowRecordingController(root: root, provider: provider)
        await #expect(throws: WindowRecordingError.permissionRequired) {
            try await recording.start(appBundleID: "dev.test.game", windowID: 21, processID: 42, name: "Seam")
        }
        #expect(TraceCatalog(roots: [root]).sessions().isEmpty)
        #expect(await provider.captureCount == 0)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
