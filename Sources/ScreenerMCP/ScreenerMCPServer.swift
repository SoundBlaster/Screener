import Foundation
import MCP

public enum ScreenerMCPServer {
    public static func make(catalog: TraceCatalog = TraceCatalog()) async -> Server {
        let server = Server(
            name: "screener-mcp",
            version: "0.1.0",
            title: "Screener",
            instructions: "Read-only access to local Screener visual-debugging traces. Start with screener.sessions, then request a timeline and one frame.",
            capabilities: .init(tools: .init())
        )

        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: [
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
            ])
        }

        await server.withMethodHandler(CallTool.self) { params in
            do {
                let args = params.arguments ?? [:]
                switch params.name {
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
