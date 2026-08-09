import Foundation

/// Extracts model identifiers from the various shapes returned by OpenAI-compatible
/// and Hermes model endpoints.
///
/// Observed shapes include:
/// - OpenAI: `{"object":"list","data":[{"id":"model"}]}`
/// - Wrapped under other keys: `{"models":[…]}`, `{"result":[…]}`
/// - A bare array: `[{"id":"model"}]`
/// - Arrays of strings: `["model-a","model-b"]`
/// - Identifier under `id`, `name`, `model`, or `model_name`
///
/// A `2xx` response has already proven authenticated access to the API surface, so the
/// interpreter is tolerant: it returns whatever identifiers it can find, and callers can
/// distinguish "structured JSON but no names" from "not an API response at all".
nonisolated enum ModelsInterpreter {
    /// The model identifiers found in the payload, or an empty array if none.
    static func modelIDs(from data: Data) -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        return modelsArray(from: json).compactMap(identifier(from:))
    }

    /// Whether the payload is a JSON object or array — a recognizable API response — even
    /// if no model identifiers could be extracted.
    static func isStructuredJSON(_ data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return false }
        return json is [Any] || json is [String: Any]
    }

    private static func modelsArray(from json: Any) -> [Any] {
        if let array = json as? [Any] {
            return array
        }
        if let object = json as? [String: Any] {
            for key in ["data", "models", "result", "results"] {
                if let array = object[key] as? [Any] {
                    return array
                }
            }
        }
        return []
    }

    private static func identifier(from element: Any) -> String? {
        if let string = element as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let object = element as? [String: Any] {
            for key in ["id", "name", "model", "model_name"] {
                if let value = object[key] as? String {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { return trimmed }
                }
            }
        }
        return nil
    }
}
