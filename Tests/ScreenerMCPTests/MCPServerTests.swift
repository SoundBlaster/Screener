import Foundation
import Testing
import MCP
import ScreenerCore
import ScreenerMCP

@Suite("Screener MCP protocol")
struct MCPServerTests {
    @Test func normalizesCodexObjectValuedExperimentalCapabilityForSDK() throws {
        let message = Data(
            #"{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{"elicitation":{"form":{},"url":{}},"experimental":{"codex/auth-change":{},"custom":"enabled"}},"clientInfo":{"name":"codex-mcp-client","title":"Codex","version":"0.156.1"}}}"#.utf8
        )

        let normalized = MCPInitializeCompatibility.normalized(message)
        let object = try #require(JSONSerialization.jsonObject(with: normalized) as? [String: Any])
        let paramsObject = try #require(object["params"] as? [String: Any])
        let capabilities = try #require(paramsObject["capabilities"] as? [String: Any])
        let experimental = try #require(capabilities["experimental"] as? [String: String])
        #expect(experimental == ["custom": "enabled"])

        let params = try JSONDecoder().decode(Initialize.Parameters.self, from: JSONSerialization.data(withJSONObject: paramsObject))
        #expect(params.protocolVersion == "2025-06-18")
        #expect(params.clientInfo.title == "Codex")
        #expect(params.capabilities.experimental == ["custom": "enabled"])
        #expect(params.capabilities.elicitation?.form != nil)
    }

    @Test func leavesCompatibleInitializeAndOtherMessagesUnchanged() throws {
        let initialize = Data(#"{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"capabilities":{"experimental":{"custom":"enabled"}}}}"#.utf8)
        let otherMethod = Data(#"{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}"#.utf8)
        #expect(MCPInitializeCompatibility.normalized(initialize) == initialize)
        #expect(MCPInitializeCompatibility.normalized(otherMethod) == otherMethod)
    }

    @Test func passesMalformedFramesThroughWithoutEndingReceiveStream() {
        let malformed = Data(#"{"jsonrpc":"2.0","method":"initialize""#.utf8)
        let validAfterMalformed = Data(#"{"jsonrpc":"2.0","method":"tools/list"}"#.utf8)

        #expect(MCPInitializeCompatibility.normalized(malformed) == malformed)
        #expect(MCPInitializeCompatibility.normalized(validAfterMalformed) == validAfterMalformed)
    }

    @Test func advertisesReadOnlyToolsAndServesSessionsTimelineAndFrame() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appending(path: "run.vtrace", directoryHint: .isDirectory)
        let manifest = TraceManifest(name: "Demo run", appBundleID: "dev.demo", platform: "iOS")
        let writer = try TraceBundleWriter(url: bundle, manifest: manifest)
        let blob = try await writer.writeBlob(try makeTestPNG(), kind: .frame, fileExtension: "png")
        let record = try await writer.append(kind: .keyframe, name: "Home", blob: blob)
        _ = try await writer.append(kind: .marker, name: "Middle")
        _ = try await writer.append(kind: .marker, name: "Latest")

        let server = await ScreenerMCPServer.make(catalog: TraceCatalog(roots: [root]))
        let transports = await InMemoryTransport.createConnectedPair()
        let client = Client(name: "ScreenerMCPTests", version: "1.0")
        try await server.start(transport: transports.server)
        _ = try await client.connect(transport: transports.client)

        let tools = try await client.listTools().tools
        #expect(tools.map(\.name).sorted() == [
            "screener.contact_sheet", "screener.frame", "screener.sessions", "screener.timeline",
        ])
        #expect(tools.allSatisfy { $0.annotations.readOnlyHint == true })

        let sessionsRequest = try await client.send(CallTool.request(.init(name: "screener.sessions")))
        let sessions = try await sessionsRequest.value
        #expect(sessions.isError != true)
        #expect(sessions.content.contains { if case .text(let text, _, _) = $0 { text.contains("Demo run") } else { false } })
        #expect(sessions.structuredContent?.objectValue?["sessions"]?.arrayValue?.count == 1)

        let timelineRequest = try await client.send(
            CallTool.request(.init(
                name: "screener.timeline",
                arguments: ["sessionID": .string(manifest.sessionID.uuidString), "limit": .int(1)]
            ))
        )
        let timeline = try await timelineRequest.value
        #expect(timeline.isError != true)
        #expect(timeline.content.contains { if case .text(let text, _, _) = $0 { text.contains("Home") } else { false } })
        let timelineObject = timeline.structuredContent?.objectValue
        #expect(timelineObject?["records"]?.arrayValue?.count == 1)
        #expect(timelineObject?["totalRecords"]?.intValue == 3)
        #expect(timelineObject?["nextOffset"]?.intValue == 1)

        let laterTimeline = try await client.callTool(
            name: "screener.timeline",
            arguments: [
                "sessionID": .string(manifest.sessionID.uuidString),
                "offset": .int(2),
                "limit": .int(1),
            ]
        )
        #expect(laterTimeline.content.contains { if case .text(let text, _, _) = $0 { text.contains("Latest") } else { false } })

        let contactSheet = try await client.send(
            CallTool.request(.init(
                name: "screener.contact_sheet",
                arguments: ["sessionID": .string(manifest.sessionID.uuidString), "maxCells": .int(12)]
            ))
        )
        let contactSheetResult = try await contactSheet.value
        #expect(contactSheetResult.isError != true)
        #expect(contactSheetResult.structuredContent?.objectValue?["cells"]?.arrayValue?.count == 1)
        #expect(contactSheetResult.content.contains { if case .image(_, "image/png", _, _) = $0 { true } else { false } })

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
