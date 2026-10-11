import Foundation
import XCTest
import UIKit

/// Reusable Simulator UI-test adapter. The consuming test supplies real navigation.
@MainActor
struct ScreenshotScenario {
    let directory: URL

    static func run(_ body: (XCUIApplication, ScreenshotScenario) throws -> Void) throws {
        let env = ProcessInfo.processInfo.environment
        guard env["SCREENER_TEST"] == "1" else { throw XCTSkip("Use the screenshot runner") }
        let orientations = try XCTUnwrap(env["SCREENER_ORIENTATIONS"]).split(separator: ",")
        let arguments = try JSONDecoder().decode([String].self, from: Data((env["SCREENER_APP_ARGUMENTS"] ?? "[]").utf8))
        let extra = try JSONDecoder().decode([String: String].self, from: Data((env["SCREENER_APP_ENVIRONMENT"] ?? "{}").utf8))
        for orientation in orientations {
            XCUIDevice.shared.orientation = .portrait
            let app = XCUIApplication()
            let runID = UUID().uuidString
            app.launchArguments = arguments + ["-AppleLanguages", "(\(try XCTUnwrap(env["SCREENER_LANGUAGE"])))",
                                               "-AppleLocale", try XCTUnwrap(env["SCREENER_LOCALE"])]
            app.launchEnvironment = extra.merging(["SCREENER_SCREENSHOTS": "1", "SCREENER_RUN_ID": runID,
                                                  "SCREENER_ORIENTATION": String(orientation)]) { _, required in required }
            app.launch()
            defer { app.terminate() }
            let directory = try container().appending(path: "Library/Caches/Screener/Screenshots/\(runID)")
            let capture = ScreenshotScenario(directory: directory)
            try capture.waitForFile("ready.json")
            XCUIDevice.shared.orientation = orientation == "portrait" ? .portrait : .landscapeLeft
            try body(app, capture)
            try capture.send("stop", presentation: "")
            try capture.waitForFile("stopped.json")
        }
    }

    static func verifyRuntimeOptOut(readyIdentifier: String) throws {
        let env = ProcessInfo.processInfo.environment
        guard env["SCREENER_TEST"] == "1" else { throw XCTSkip("Use the screenshot runner") }
        let runID = UUID().uuidString
        let app = XCUIApplication()
        app.launchEnvironment = ["SCREENER_RUN_ID": runID]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.descendants(matching: .any)[readyIdentifier].waitForExistence(timeout: 20))
        XCTAssertFalse(FileManager.default.fileExists(atPath:
            try container().appending(path: "Library/Caches/Screener/Screenshots/\(runID)").path))
    }

    func checkpoint(_ name: String, presentation: String) throws {
        try? FileManager.default.removeItem(at: directory.appending(path: "response.json"))
        try send(name, presentation: presentation)
        try waitForFile("response.json")
        let result = try JSONDecoder().decode([String: String].self,
            from: Data(contentsOf: directory.appending(path: "response.json")))
        guard result["name"] == name && result["state"] == "complete" else {
            XCTFail(result["error"] ?? "Unexpected checkpoint acknowledgement")
            throw CocoaError(.fileReadCorruptFile)
        }
        let system = directory.appending(path: "system")
        try FileManager.default.createDirectory(at: system, withIntermediateDirectories: true)
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: system.appending(path: name + ".png"), options: .atomic)
    }

    private func send(_ name: String, presentation: String) throws {
        try JSONEncoder().encode(["name": name, "presentation": presentation])
            .write(to: directory.appending(path: "request.json"), options: .atomic)
    }

    private func waitForFile(_ name: String) throws {
        let url = directory.appending(path: name)
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: url.path) { return }
            if FileManager.default.fileExists(atPath: directory.appending(path: "failure.json").path) {
                throw CocoaError(.fileReadCorruptFile)
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTFail("Timed out waiting for \(name)")
        throw CocoaError(.fileReadNoSuchFile)
    }

    private static func container() throws -> URL {
        let env = ProcessInfo.processInfo.environment
        let root = URL(fileURLWithPath: try XCTUnwrap(env["SCREENER_CONTAINERS_ROOT"]))
        let bundle = try XCTUnwrap(env["SCREENER_BUNDLE_ID"])
        let directories = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        return try XCTUnwrap(directories.first { directory in
            guard let bytes = try? Data(contentsOf: directory.appending(path: ".com.apple.mobile_container_manager.metadata.plist")),
                  let metadata = try? PropertyListSerialization.propertyList(from: bytes, format: nil) as? [String: Any]
            else { return false }
            return metadata["MCMMetadataIdentifier"] as? String == bundle
        })
    }
}
