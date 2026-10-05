import Foundation
import Testing
import ScreenerCore
@testable import ScreenerKit

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
}
