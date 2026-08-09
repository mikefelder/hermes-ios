import Foundation

/// A parsed Markdown block. Messages render as typed parts rather than one
/// attributed string, so code, tables, and quotes get purpose-built views.
nonisolated enum MarkdownBlock: Equatable, Sendable, Identifiable {
    case heading(level: Int, inline: String)
    case paragraph(inline: String)
    case bulletList(items: [String])
    case orderedList(items: [String])
    case quote(lines: [String])
    case code(language: String?, content: String)
    case table(headers: [String], rows: [[String]])
    case rule

    var id: String {
        switch self {
        case let .heading(level, inline): "h\(level):\(inline)"
        case let .paragraph(inline): "p:\(inline)"
        case let .bulletList(items): "ul:\(items.joined(separator: "\u{1}"))"
        case let .orderedList(items): "ol:\(items.joined(separator: "\u{1}"))"
        case let .quote(lines): "q:\(lines.joined(separator: "\u{1}"))"
        case let .code(language, content): "code:\(language ?? ""):\(content)"
        case let .table(headers, rows): "t:\(headers.joined(separator: "\u{1}")):\(rows.count)"
        case .rule: "hr"
        }
    }
}

/// Splits assistant text into ``MarkdownBlock``s.
///
/// The parser is streaming-tolerant: an unterminated fence is emitted as a code
/// block so a partially received message still renders sensibly. Raw HTML is
/// stripped and images are replaced with an inert placeholder, because the render
/// surface must never fetch remote resources or execute embedded content.
nonisolated struct MarkdownParser {
    func parse(_ source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if let fence = fenceLanguage(trimmed) {
                var content: [String] = []
                index += 1
                while index < lines.count, !isFence(lines[index].trimmingCharacters(in: .whitespaces)) {
                    content.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 }
                blocks.append(.code(language: fence, content: content.joined(separator: "\n")))
                continue
            }

            if isRule(trimmed) {
                blocks.append(.rule)
                index += 1
                continue
            }

            if let heading = heading(trimmed) {
                blocks.append(.heading(level: heading.level, inline: sanitize(heading.text)))
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                var quoted: [String] = []
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard candidate.hasPrefix(">") else { break }
                    quoted.append(sanitize(String(candidate.dropFirst()).trimmingCharacters(in: .whitespaces)))
                    index += 1
                }
                blocks.append(.quote(lines: quoted))
                continue
            }

            if isTableRow(trimmed), index + 1 < lines.count,
               isTableDelimiter(lines[index + 1].trimmingCharacters(in: .whitespaces)) {
                let headers = tableCells(trimmed).map(sanitize)
                index += 2
                var rows: [[String]] = []
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard isTableRow(candidate) else { break }
                    rows.append(tableCells(candidate).map(sanitize))
                    index += 1
                }
                blocks.append(.table(headers: headers, rows: rows))
                continue
            }

            if bulletContent(trimmed) != nil {
                var items: [String] = []
                while index < lines.count,
                      let item = bulletContent(lines[index].trimmingCharacters(in: .whitespaces)) {
                    items.append(sanitize(item))
                    index += 1
                }
                blocks.append(.bulletList(items: items))
                continue
            }

            if orderedContent(trimmed) != nil {
                var items: [String] = []
                while index < lines.count,
                      let item = orderedContent(lines[index].trimmingCharacters(in: .whitespaces)) {
                    items.append(sanitize(item))
                    index += 1
                }
                blocks.append(.orderedList(items: items))
                continue
            }

            var paragraph: [String] = []
            while index < lines.count {
                let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                if candidate.isEmpty || startsBlock(candidate) { break }
                paragraph.append(candidate)
                index += 1
            }
            blocks.append(.paragraph(inline: sanitize(paragraph.joined(separator: " "))))
        }

        return blocks
    }

    private func startsBlock(_ line: String) -> Bool {
        isFence(line)
            || isRule(line)
            || heading(line) != nil
            || line.hasPrefix(">")
            || bulletContent(line) != nil
            || orderedContent(line) != nil
    }

    private func isFence(_ line: String) -> Bool {
        line.hasPrefix("```") || line.hasPrefix("~~~")
    }

    private func fenceLanguage(_ line: String) -> String?? {
        guard isFence(line) else { return nil }
        let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        return .some(language.isEmpty ? nil : language)
    }

    private func isRule(_ line: String) -> Bool {
        let stripped = line.replacingOccurrences(of: " ", with: "")
        guard stripped.count >= 3 else { return false }
        return stripped.allSatisfy { $0 == "-" } || stripped.allSatisfy { $0 == "*" } || stripped.allSatisfy { $0 == "_" }
    }

    private func heading(_ line: String) -> (level: Int, text: String)? {
        guard line.hasPrefix("#") else { return nil }
        let hashes = line.prefix { $0 == "#" }
        guard hashes.count <= 6, line.dropFirst(hashes.count).hasPrefix(" ") else { return nil }
        return (hashes.count, String(line.dropFirst(hashes.count)).trimmingCharacters(in: .whitespaces))
    }

    private func bulletContent(_ line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        return nil
    }

    private func orderedContent(_ line: String) -> String? {
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        return String(rest.dropFirst(2))
    }

    private func isTableRow(_ line: String) -> Bool {
        line.hasPrefix("|") && line.dropFirst().contains("|")
    }

    private func isTableDelimiter(_ line: String) -> Bool {
        guard isTableRow(line) else { return false }
        let cells = tableCells(line)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let stripped = cell.replacingOccurrences(of: " ", with: "")
            return !stripped.isEmpty && stripped.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }

    private func tableCells(_ line: String) -> [String] {
        var body = line
        if body.hasPrefix("|") { body.removeFirst() }
        if body.hasSuffix("|") { body.removeLast() }
        return body.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Remove content the render surface must never process: raw HTML tags and
    /// image references, which would otherwise trigger a remote fetch.
    private func sanitize(_ text: String) -> String {
        MarkdownSanitizer.sanitizeInline(text)
    }
}

nonisolated enum MarkdownSanitizer {
    /// Link schemes the app is willing to hand to the system.
    static let allowedSchemes: Set<String> = ["https"]

    static func isAllowed(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return allowedSchemes.contains(scheme)
    }

    /// Strips raw HTML and replaces images with an inert label naming the host, so
    /// no remote resource is fetched and no markup reaches a renderer.
    static func sanitizeInline(_ text: String) -> String {
        var result = replaceImages(in: text)
        result = stripHTMLTags(in: result)
        return result
    }

    private static func replaceImages(in text: String) -> String {
        guard text.contains("![") else { return text }
        var output = ""
        var remainder = Substring(text)

        while let start = remainder.range(of: "![") {
            output += remainder[remainder.startIndex..<start.lowerBound]
            let afterMarker = remainder[start.upperBound...]
            guard let altEnd = afterMarker.range(of: "]("),
                  let urlEnd = afterMarker[altEnd.upperBound...].firstIndex(of: ")") else {
                output += remainder[start.lowerBound...]
                return output
            }
            let target = String(afterMarker[altEnd.upperBound..<urlEnd])
            let host = URL(string: target)?.host ?? "remote host"
            output += "[image not loaded — \(host)]"
            remainder = afterMarker[afterMarker.index(after: urlEnd)...]
        }

        output += remainder
        return output
    }

    private static func stripHTMLTags(in text: String) -> String {
        guard text.contains("<") else { return text }
        var output = ""
        var insideTag = false
        for character in text {
            if character == "<" {
                insideTag = true
            } else if character == ">" {
                insideTag = false
            } else if !insideTag {
                output.append(character)
            }
        }
        return output
    }
}
