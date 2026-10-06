import Foundation
import Logging
import MCP

/// A stdio transport that filters initialization fields unsupported by the
/// pinned MCP Swift SDK before they reach its decoder.
public actor CodexCompatibleStdioTransport: Transport {
    private let underlying: StdioTransport
    public nonisolated let logger: Logger

    public init() {
        let logger = Logger(label: "screener.mcp.stdio")
        self.logger = logger
        self.underlying = StdioTransport(logger: logger)
    }

    public func connect() async throws {
        try await underlying.connect()
    }

    public func disconnect() async {
        await underlying.disconnect()
    }

    public func send(_ data: Data) async throws {
        try await underlying.send(data)
    }

    public func receive() -> AsyncThrowingStream<Data, Swift.Error> {
        let underlying = self.underlying
        return AsyncThrowingStream { continuation in
            let forwardingTask = Task {
                do {
                    let messages = await underlying.receive()
                    for try await message in messages {
                        continuation.yield(MCPInitializeCompatibility.normalized(message))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                forwardingTask.cancel()
            }
        }
    }
}
