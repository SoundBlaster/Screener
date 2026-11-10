import Foundation
import MCP
import ScreenerMCP

@main
enum ScreenerMCPCommand {
    static func main() async throws {
        let options = try options(from: Array(CommandLine.arguments.dropFirst()))
        var roots = options.roots.isEmpty ? TraceCatalog.defaultRoots : options.roots
        var recording: WindowRecordingController?
        if let directory = options.recordingsDirectory {
            recording = try makeRecordingController(in: directory)
            roots.append(directory)
        }
        let server = await ScreenerMCPServer.make(catalog: TraceCatalog(roots: roots), recording: recording)
        try await server.start(transport: CodexCompatibleStdioTransport())
        await server.waitUntilCompleted()
    }

    private static func makeRecordingController(in directory: URL) throws -> WindowRecordingController {
        #if os(macOS)
        guard #available(macOS 14, *) else { throw CommandError.unsupportedOS }
        return WindowRecordingController(root: directory, provider: SystemWindowCaptureProvider())
        #else
        throw CommandError.unsupportedOS
        #endif
    }

    private struct Options {
        var roots: [URL] = []
        var recordingsDirectory: URL?
    }

    private static func options(from arguments: [String]) throws -> Options {
        var options = Options()
        var index = 0
        while index < arguments.count {
            guard arguments.indices.contains(index + 1) else { throw CommandError.usage }
            let path = NSString(string: arguments[index + 1]).expandingTildeInPath
            guard !path.isEmpty else { throw CommandError.usage }
            let directory = URL(fileURLWithPath: path, isDirectory: true)
            switch arguments[index] {
            case "--traces-dir": options.roots.append(directory)
            case "--recordings-dir":
                guard options.recordingsDirectory == nil else { throw CommandError.usage }
                options.recordingsDirectory = directory
            default: throw CommandError.usage
            }
            index += 2
        }
        return options
    }

    private enum CommandError: Error, LocalizedError {
        case usage, unsupportedOS
        var errorDescription: String? {
            switch self {
            case .usage: "Usage: screener-mcp [--traces-dir PATH]... [--recordings-dir PATH]"
            case .unsupportedOS: "Window recording requires macOS 14 or later."
            }
        }
    }
}
