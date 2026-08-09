import Foundation

/// Produces a short, single-line, length-limited preview of an HTTP response body for
/// diagnostics. Whitespace runs are collapsed so an HTML page or error text is legible on
/// one line, and the output is bounded to avoid dumping large bodies into the UI.
nonisolated enum ResponsePreview {
    static func text(from data: Data, limit: Int = 120) -> String {
        guard !data.isEmpty else { return "(empty body)" }
        let raw = String(decoding: data.prefix(limit * 3), as: UTF8.self)
        let collapsed = raw.unicodeScalars.map {
            CharacterSet.whitespacesAndNewlines.contains($0) ? " " : Character($0)
        }.reduce(into: "") { $0.append($1) }
        let normalized = collapsed
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty else { return "(non-text body)" }
        return normalized.count > limit ? String(normalized.prefix(limit)) + "…" : normalized
    }
}
