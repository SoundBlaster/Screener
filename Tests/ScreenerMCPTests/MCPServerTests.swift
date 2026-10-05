import Foundation
import Testing
import MCP
import ScreenerCore
import ScreenerMCP

@Suite("Screener MCP protocol")
struct MCPServerTests {
    @Test func advertisesReadOnlyToolsAndServesSessionsTimelineAndFrame() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appending(path: "run.vtrace", directoryHint: .isDirectory)
        let manifest = TraceManifest(name: "Demo run", appBundleID: "dev.demo", platform: "iOS")
        let writer = try TraceBundleWriter(url: bundle, manifest: manifest)
        let blob = try await writer.writeBlob(Data([0x01, 0x02]), kind: .frame, fileExtension: "png")
        let record = try await writer.append(kind: .keyframe, name: "Home", blob: blob)

        let server = await ScreenerMCPServer.make(catalog: TraceCatalog(roots: [root]))
        let transports = await InMemoryTransport.createConnectedPair()
        let client = Client(name: "ScreenerMCPTests", version: "1.0")
        try await server.start(transport: transports.server)
        _ = try await client.connect(transport: transports.client)

        let tools = try await client.listTools().tools
        #expect(tools.map(\.name).sorted() == ["screener.frame", "screener.sessions", "screener.timeline"])
        #expect(tools.allSatisfy { $0.annotations.readOnlyHint == true })

        let sessions = try await client.callTool(name: "screener.sessions")
        #expect(sessions.isError != true)
        #expect(sessions.content.contains { if case .text(let text, _, _) = $0 { text.contains("Demo run") } else { false } })

        let timeline = try await client.callTool(
            name: "screener.timeline",
            arguments: ["sessionID": .string(manifest.sessionID.uuidString), "limit": .int(10)]
        )
        #expect(timeline.isError != true)
        #expect(timeline.content.contains { if case .text(let text, _, _) = $0 { text.contains("Home") } else { false } })

        let image = try await client.callTool(
            name: "screener.frame",
            arguments: ["sessionID": .string(manifest.sessionID.uuidString), "recordID": .string(record.id.uuidString)]
        )
        #expect(image.isError != true)
        #expect(image.content.contains { if case .image(_, "image/png", _, _) = $0 { true } else { false } })

        await server.stop()
        await client.disconnect()
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
