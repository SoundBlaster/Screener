import Foundation
import MCP
import ScreenerMCP

@main
enum ScreenerMCPCommand {
    static func main() async throws {
        let roots = try traceRoots(from: Array(CommandLine.arguments.dropFirst()))
        let server = await ScreenerMCPServer.make(catalog: TraceCatalog(roots: roots))
        try await server.start(transport: StdioTransport())
        await server.waitUntilCompleted()
    }

    private static func traceRoots(from arguments: [String]) throws -> [URL] {
        var roots: [URL] = []
        var index = 0
        while index < arguments.count {
            guard arguments[index] == "--traces-dir", arguments.indices.contains(index + 1) else {
                throw CommandError.usage
            }
            let path = NSString(string: arguments[index + 1]).expandingTildeInPath
            roots.append(URL(fileURLWithPath: path, isDirectory: true))
            index += 2
        }
        return roots.isEmpty ? TraceCatalog.defaultRoots : roots
    }

    private enum CommandError: Error, LocalizedError {
        case usage
        var errorDescription: String? { "Usage: screener-mcp [--traces-dir PATH]..." }
    }
}
