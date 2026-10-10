import Foundation

/// Session identity and producer metadata for versioned trace storage.
public struct TraceManifest: Codable, Sendable, Equatable {
    public static let currentFormatVersion = 1

    public let formatVersion: Int
    public let sessionID: UUID
    public let name: String
    public let appBundleID: String
    public let platform: String
    public let startedAt: Date
    public let screenerVersion: String

    public init(
        sessionID: UUID = UUID(),
        name: String,
        appBundleID: String,
        platform: String,
        startedAt: Date = .now,
        screenerVersion: String = "0.1.0"
    ) {
        self.formatVersion = Self.currentFormatVersion
        self.sessionID = sessionID
        self.name = name
        self.appBundleID = appBundleID
        self.platform = platform
        self.startedAt = startedAt
        self.screenerVersion = screenerVersion
    }
}
