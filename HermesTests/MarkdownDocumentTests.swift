import Foundation
import Testing
@testable import Hermes

@Suite("Markdown parsing")
struct MarkdownDocumentTests {
    private let parser = MarkdownParser()

    @Test("Headings, paragraphs, and rules are separated")
    func parsesBasicBlocks() {
        let blocks = parser.parse("# Title\n\nSome text.\n\n---\n")

        #expect(blocks == [
            .heading(level: 1, inline: "Title"),
            .paragraph(inline: "Some text."),
            .rule
        ])
    }

    @Test("Bullet and ordered lists group their items")
    func parsesLists() {
        let blocks = parser.parse("- one\n- two\n\n1. first\n2. second")

        #expect(blocks == [
            .bulletList(items: ["one", "two"]),
            .orderedList(items: ["first", "second"])
        ])
    }

    @Test("Fenced code keeps its language and exact content")
    func parsesFencedCode() {
        let blocks = parser.parse("```swift\nlet x = 1\n\nlet y = 2\n```")

        #expect(blocks == [.code(language: "swift", content: "let x = 1\n\nlet y = 2")])
    }

    @Test("An unterminated fence still renders, so partial streams are readable")
    func toleratesUnterminatedFence() {
        let blocks = parser.parse("```python\nprint(1)")

        #expect(blocks == [.code(language: "python", content: "print(1)")])
    }

    @Test("Markdown inside a fence is never treated as structure")
    func fenceContentIsOpaque() {
        let blocks = parser.parse("```\n# not a heading\n- not a list\n```")

        #expect(blocks == [.code(language: nil, content: "# not a heading\n- not a list")])
    }

    @Test("Tables require a delimiter row and keep their cells")
    func parsesTable() {
        let blocks = parser.parse("| A | B |\n| --- | --- |\n| 1 | 2 |")

        #expect(blocks == [.table(headers: ["A", "B"], rows: [["1", "2"]])])
    }

    @Test("A pipe row without a delimiter stays a paragraph")
    func pipeWithoutDelimiterIsParagraph() {
        let blocks = parser.parse("| not | a table |")

        #expect(blocks == [.paragraph(inline: "| not | a table |")])
    }

    @Test("Block quotes collect consecutive lines")
    func parsesQuote() {
        let blocks = parser.parse("> first\n> second")

        #expect(blocks == [.quote(lines: ["first", "second"])])
    }

    @Test("Raw HTML is stripped before rendering")
    func stripsRawHTML() {
        let blocks = parser.parse("Hello <script>alert(1)</script> world")

        #expect(blocks == [.paragraph(inline: "Hello alert(1) world")])
    }

    @Test("Images become inert placeholders naming the host and are never fetched")
    func replacesImages() {
        let blocks = parser.parse("before ![alt](https://tracker.example.com/pixel.png) after")

        #expect(blocks == [.paragraph(inline: "before [image not loaded — tracker.example.com] after")])
    }
}

@Suite("Markdown link safety")
struct MarkdownSanitizerTests {
    @Test("Only HTTPS destinations are offered to the system")
    func allowsHTTPSOnly() throws {
        #expect(MarkdownSanitizer.isAllowed(try #require(URL(string: "https://example.com"))) == true)
        #expect(MarkdownSanitizer.isAllowed(try #require(URL(string: "http://example.com"))) == false)
    }

    @Test("Dangerous and unknown schemes are refused")
    func blocksDangerousSchemes() throws {
        for candidate in [
            "javascript:alert(1)",
            "data:text/html,<script>alert(1)</script>",
            "file:///etc/passwd",
            "hermes://approve/all"
        ] {
            let url = try #require(URL(string: candidate))
            #expect(MarkdownSanitizer.isAllowed(url) == false, "\(candidate) must not be openable")
        }
    }

    @Test("A refused scheme loses its link attribute but keeps its text")
    func stripsDisallowedLinkAttributes() {
        let attributed = MarkdownInline.attributed("[tap me](javascript:alert(1))")

        #expect(String(attributed.characters) == "tap me")
        #expect(attributed.runs.allSatisfy { $0.link == nil })
    }

    @Test("An allowed link keeps its destination")
    func keepsAllowedLink() throws {
        let attributed = MarkdownInline.attributed("[docs](https://example.com/docs)")

        let links = attributed.runs.compactMap(\.link)
        #expect(links == [try #require(URL(string: "https://example.com/docs"))])
    }
}
