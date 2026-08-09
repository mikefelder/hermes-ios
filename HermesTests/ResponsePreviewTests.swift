import Foundation
import Testing
@testable import Hermes

@Suite("Response preview")
struct ResponsePreviewTests {
    private func data(_ string: String) -> Data { Data(string.utf8) }

    @Test("An empty body is labeled")
    func emptyBody() {
        #expect(ResponsePreview.text(from: Data()) == "(empty body)")
    }

    @Test("Collapses whitespace and newlines to a single line")
    func collapsesWhitespace() {
        #expect(ResponsePreview.text(from: data("<html>\n  <body>  Not Found </body>\n</html>")) == "<html> <body> Not Found </body> </html>")
    }

    @Test("Truncates long bodies with an ellipsis")
    func truncates() {
        let long = String(repeating: "a", count: 500)
        let preview = ResponsePreview.text(from: data(long), limit: 20)
        #expect(preview.count == 21) // 20 chars + ellipsis
        #expect(preview.hasSuffix("…"))
    }

    @Test("Whitespace-only bodies are labeled non-text")
    func whitespaceOnly() {
        #expect(ResponsePreview.text(from: data("   \n\t  ")) == "(non-text body)")
    }

    @Test("Short text passes through trimmed")
    func shortText() {
        #expect(ResponsePreview.text(from: data("  ok  ")) == "ok")
    }
}
