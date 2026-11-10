import Foundation
import MCP

/// Constructs a local trace server with optional window recording.
public enum ScreenerMCPServer {
    /// Creates a server whose tool handlers read from the supplied catalog.
    /// The caller connects the returned server to its chosen transport.
    public static func make(catalog: TraceCatalog = TraceCatalog(), recording: WindowRecordingController? = nil) async -> Server {
        let server = Server(
            name: "screener-mcp",
            version: "0.2.0",
            title: "Screener",
            instructions: recording == nil
                ? "Read-only access to local Screener visual-debugging traces. Start with screener.sessions, then request a timeline and one frame."
                : "Inspect traces or explicitly record checkpoints from one selected application window. Recording never starts automatically.",
            capabilities: .init(tools: .init())
        )

        await server.withMethodHandler(ListTools.self) { _ in
            let readTools: [Tool] = [
                Tool(
                    name: "screener.sessions",
                    title: "List Screener sessions",
                    description: "List locally recorded Screener sessions without exposing filesystem paths.",
                    inputSchema: .object(["type": .string("object"), "properties": .object([:])]),
                    annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
                ),
                Tool(
                    name: "screener.timeline",
                    title: "Read session timeline",
                    description: "Read chronological events and frame metadata for one session. Use nextOffset to page through long sessions. Limit is clamped to 1...2000.",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "sessionID": .object(["type": .string("string"), "format": .string("uuid")]),
                            "offset": .object(["type": .string("integer"), "minimum": .int(0)]),
                            "limit": .object(["type": .string("integer"), "minimum": .int(1), "maximum": .int(2000)]),
                        ]),
                        "required": .array([.string("sessionID")]),
                    ]),
                    annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
                ),
                Tool(
                    name: "screener.frame",
                    title: "Read one frame",
                    description: "Return one recorded thumbnail or keyframe image by session and timeline record UUID.",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "sessionID": .object(["type": .string("string"), "format": .string("uuid")]),
                            "recordID": .object(["type": .string("string"), "format": .string("uuid")]),
                        ]),
                        "required": .array([.string("sessionID"), .string("recordID")]),
                    ]),
                    annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
                ),
                Tool(
                    name: "screener.contact_sheet",
                    title: "Build a contact sheet",
                    description: "Return a chronological grid of up to 24 downsampled frames. Cell numbers map to the structured cells array; pages use frame offsets.",
                    inputSchema: .object([
                        "type": .string("object"),
                        "properties": .object([
                            "sessionID": .object(["type": .string("string"), "format": .string("uuid")]),
                            "offset": .object(["type": .string("integer"), "minimum": .int(0)]),
                            "maxCells": .object(["type": .string("integer"), "minimum": .int(1), "maximum": .int(24)]),
                            "columns": .object(["type": .string("integer"), "minimum": .int(1), "maximum": .int(6)]),
                        ]),
                        "required": .array([.string("sessionID")]),
                    ]),
                    annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
                ),
            ]
            return ListTools.Result(tools: readTools + (recording == nil ? [] : recordingTools()))
        }

        await server.withMethodHandler(CallTool.self) { params in
            do {
                let args = params.arguments ?? [:]
                switch params.name {
                case "screener.windows":
                    guard let recording else { return errorResult("Window recording is not enabled") }
                    guard let appBundleID = args["appBundleID"]?.stringValue else { return errorResult("appBundleID is required") }
                    let result = WindowListOutput(windows: try await recording.windows(appBundleID: appBundleID))
                    return try CallTool.Result(content: [text(json(result))], structuredContent: MCP.Value(result))
                case "screener.window_start":
                    guard let recording else { return errorResult("Window recording is not enabled") }
                    guard let appBundleID = args["appBundleID"]?.stringValue,
                          let windowValue = args["windowID"]?.intValue, let windowID = UInt32(exactly: windowValue),
                          let processValue = args["processID"]?.intValue, let processID = Int32(exactly: processValue),
                          let name = args["name"]?.stringValue else { return errorResult("appBundleID, windowID, processID and name are required") }
                    let result = try await recording.start(appBundleID: appBundleID, windowID: windowID, processID: processID, name: name)
                    return try CallTool.Result(content: [text(json(result))], structuredContent: MCP.Value(result))
                case "screener.window_capture":
                    guard let recording else { return errorResult("Window recording is not enabled") }
                    guard let rawID = args["sessionID"]?.stringValue, let sessionID = UUID(uuidString: rawID),
                          let reason = args["reason"]?.stringValue else { return errorResult("sessionID and reason are required") }
                    let result = try await recording.capture(sessionID: sessionID, reason: reason)
                    return try CallTool.Result(content: [text(json(result))], structuredContent: MCP.Value(result))
                case "screener.window_stop":
                    guard let recording else { return errorResult("Window recording is not enabled") }
                    guard let rawID = args["sessionID"]?.stringValue, let sessionID = UUID(uuidString: rawID) else { return errorResult("sessionID must be a UUID") }
                    let result = try await recording.stop(sessionID: sessionID)
                    return try CallTool.Result(content: [text(json(result))], structuredContent: MCP.Value(result))
                case "screener.sessions":
                    let sessions = catalog.sessions()
                    let output = SessionsOutput(sessions: sessions)
                    return try CallTool.Result(content: [text(json(output))], structuredContent: MCP.Value(output))
                case "screener.timeline":
                    guard let rawID = args["sessionID"]?.stringValue, let sessionID = UUID(uuidString: rawID) else {
                        return errorResult("sessionID must be a UUID")
                    }
                    let offset = args["offset"]?.intValue ?? 0
                    let limit = args["limit"]?.intValue ?? 500
                    let page = try catalog.timelinePage(sessionID: sessionID, offset: offset, limit: limit)
                    return try CallTool.Result(content: [text(json(page))], structuredContent: MCP.Value(page))
                case "screener.frame":
                    guard let rawSessionID = args["sessionID"]?.stringValue,
                          let sessionID = UUID(uuidString: rawSessionID),
                          let rawRecordID = args["recordID"]?.stringValue,
                          let recordID = UUID(uuidString: rawRecordID) else {
                        return errorResult("sessionID and recordID must be UUIDs")
                    }
                    let frame = try catalog.frame(sessionID: sessionID, recordID: recordID)
                    let metadata = FrameMetadata(
                        sessionID: sessionID,
                        recordID: recordID,
                        sequence: frame.record.sequence,
                        timestamp: frame.record.timestamp,
                        name: frame.record.name,
                        kind: frame.record.kind.rawValue,
                        mimeType: frame.mimeType
                    )
                    return try CallTool.Result(
                        content: [text(json(metadata)), .image(data: frame.data.base64EncodedString(), mimeType: frame.mimeType, annotations: nil, _meta: nil)],
                        structuredContent: MCP.Value(metadata)
                    )
                case "screener.contact_sheet":
                    guard let rawSessionID = args["sessionID"]?.stringValue,
                          let sessionID = UUID(uuidString: rawSessionID) else {
                        return errorResult("sessionID must be a UUID")
                    }
                    let result = try catalog.contactSheet(
                        sessionID: sessionID,
                        offset: args["offset"]?.intValue ?? 0,
                        maxCells: args["maxCells"]?.intValue ?? 24,
                        columns: args["columns"]?.intValue ?? 4
                    )
                    return try CallTool.Result(
                        content: [
                            text(json(result.page)),
                            .image(data: result.imageData.base64EncodedString(), mimeType: "image/png", annotations: nil, _meta: nil),
                        ],
                        structuredContent: MCP.Value(result.page)
                    )
                default:
                    return errorResult("Unknown tool: \(params.name)")
                }
            } catch let toolError {
                return errorResult(toolError.localizedDescription)
            }
        }
        return server
    }

    private static func recordingTools() -> [Tool] {
        let string: MCP.Value = .object(["type": .string("string")])
        let positiveInteger: MCP.Value = .object(["type": .string("integer"), "minimum": .int(1)])
        let sessionID: MCP.Value = .object(["type": .string("string"), "format": .string("uuid")])
        let annotation = Tool.Annotations(readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false)
        return [
            Tool(name: "screener.windows", title: "Find application windows", description: "List on-screen windows for one exact bundle identifier; requires existing screen-capture access.", inputSchema: .object([
                "type": .string("object"), "properties": .object(["appBundleID": string]), "required": .array([.string("appBundleID")]),
            ]), annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)),
            Tool(name: "screener.window_start", title: "Start window trace", description: "Start one explicit window trace without taking a frame or starting a timer.", inputSchema: .object([
                "type": .string("object"), "properties": .object(["appBundleID": string, "windowID": positiveInteger, "processID": positiveInteger, "name": string]),
                "required": .array([.string("appBundleID"), .string("windowID"), .string("processID"), .string("name")]),
            ]), annotations: annotation),
            Tool(name: "screener.window_capture", title: "Capture window checkpoint", description: "Capture one named checkpoint for the active window trace.", inputSchema: .object([
                "type": .string("object"), "properties": .object(["sessionID": sessionID, "reason": string]),
                "required": .array([.string("sessionID"), .string("reason")]),
            ]), annotations: annotation),
            Tool(name: "screener.window_stop", title: "Stop window trace", description: "Finish the active window trace.", inputSchema: .object([
                "type": .string("object"), "properties": .object(["sessionID": sessionID]), "required": .array([.string("sessionID")]),
            ]), annotations: annotation),
        ]
    }

    private struct WindowListOutput: Codable, Sendable {
        let windows: [RecordableWindow]
    }

    private static func text(_ value: String) -> Tool.Content {
        .text(text: value, annotations: nil, _meta: nil)
    }

    private static func errorResult(_ value: String) -> CallTool.Result {
        CallTool.Result(content: [text(value)], isError: true)
    }

    private static func json<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private struct FrameMetadata: Codable, Sendable {
        let sessionID: UUID
        let recordID: UUID
        let sequence: UInt64
        let timestamp: Date
        let name: String
        let kind: String
        let mimeType: String
    }

    private struct SessionsOutput: Codable, Sendable {
        let sessions: [TraceSession]
    }
}
