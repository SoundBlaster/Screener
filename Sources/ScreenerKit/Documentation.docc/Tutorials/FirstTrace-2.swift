#if DEBUG && canImport(UIKit)
import UIKit
import ScreenerKit

@MainActor
func recordFirstTrace(in window: UIWindow) async throws -> URL {
    let recorder = Screener()
    let trace = try await recorder.startSession(
        name: "first-trace",
        appBundleID: Bundle.main.bundleIdentifier ?? "example.app",
        tracesDirectory: URL.documentsDirectory.appending(path: "ScreenerTraces")
    )
    do {
        try await recorder.mark("Reproduction.started")
        try await recorder.stopSession()
        return trace
    } catch {
        try? await recorder.stopSession()
        throw error
    }
}
#endif
