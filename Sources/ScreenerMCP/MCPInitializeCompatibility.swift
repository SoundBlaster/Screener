import Foundation
import MCP

/// Adapts experimental initialization capabilities to the shape accepted by
/// the current MCP Swift SDK.
public enum MCPInitializeCompatibility {
    /// The SDK currently decodes experimental capabilities as `[String: String]`.
    /// Codex may send object-valued feature declarations, which the server does
    /// not consume. Preserve string-valued entries and remove unsupported values
    /// before the SDK decodes the initialization request.
    public static func normalized(_ messageData: Data) -> Data {
        guard var message = (try? JSONSerialization.jsonObject(with: messageData)) as? [String: Any],
              message["method"] as? String == "initialize",
              var params = message["params"] as? [String: Any],
              var capabilities = params["capabilities"] as? [String: Any],
              let experimental = capabilities["experimental"] as? [String: Any],
              !experimental.values.allSatisfy({ $0 is String }) else {
            return messageData
        }

        let supportedValues = experimental.reduce(into: [String: String]()) { result, entry in
            if let value = entry.value as? String {
                result[entry.key] = value
            }
        }
        if supportedValues.isEmpty {
            capabilities.removeValue(forKey: "experimental")
        } else {
            capabilities["experimental"] = supportedValues
        }
        params["capabilities"] = capabilities
        message["params"] = params
        return (try? JSONSerialization.data(withJSONObject: message, options: [.sortedKeys])) ?? messageData
    }
}
