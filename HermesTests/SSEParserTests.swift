import Foundation
import Testing
@testable import Hermes

@Suite("SSE parser")
struct SSEParserTests {
    /// Feed an entire string as one UTF-8 chunk.
    private func events(_ text: String) throws -> [SSEEvent] {
        var parser = SSEParser()
        return try parser.consume(Array(text.utf8))
    }

    @Test("Parses a single message event")
    func singleEvent() throws {
        let result = try events("data: hello\n\n")
        #expect(result == [SSEEvent(type: "message", data: "hello", id: nil, retry: nil)])
    }

    @Test("Joins multiple data lines with newlines")
    func multilineData() throws {
        let result = try events("data: a\ndata: b\ndata: c\n\n")
        #expect(result.count == 1)
        #expect(result.first?.data == "a\nb\nc")
    }

    @Test("Strips exactly one leading space after the colon")
    func leadingSpace() throws {
        #expect(try events("data:hello\n\n").first?.data == "hello")
        #expect(try events("data:  hello\n\n").first?.data == " hello")
    }

    @Test("Applies event, id, and retry fields")
    func metadataFields() throws {
        let result = try events("event: ping\nid: 42\nretry: 3000\ndata: x\n\n")
        #expect(result == [SSEEvent(type: "ping", data: "x", id: "42", retry: 3000)])
    }

    @Test("Ignores comment and heartbeat lines")
    func heartbeat() throws {
        #expect(try events(": keep-alive\n\n").isEmpty)
        let result = try events(": comment\ndata: y\n\n")
        #expect(result.first?.data == "y")
    }

    @Test("Does not dispatch an event that carried no data")
    func metadataOnlyDoesNotDispatch() throws {
        #expect(try events("event: ping\n\n").isEmpty)
        #expect(try events("id: 7\n\n").isEmpty)
    }

    @Test("A bare data field dispatches an empty payload")
    func emptyDataDispatches() throws {
        let result = try events("data:\n\n")
        #expect(result == [SSEEvent(type: "message", data: "", id: nil, retry: nil)])
    }

    @Test("Accepts CRLF, LF, and lone CR line endings", arguments: [
        "data: x\r\n\r\n",
        "data: x\n\n",
        "data: a\rdata: b\n\n"
    ])
    func lineEndings(stream: String) throws {
        let result = try events(stream)
        #expect(!result.isEmpty)
    }

    @Test("Lone CR joins multiple data lines")
    func loneCRData() throws {
        let result = try events("data: a\rdata: b\n\n")
        #expect(result.first?.data == "a\nb")
    }

    @Test("Emits multiple events from one chunk")
    func multipleEvents() throws {
        let result = try events("data: a\n\ndata: b\n\n")
        #expect(result.map(\.data) == ["a", "b"])
    }

    @Test("Passes the [DONE] sentinel through as data")
    func donePassthrough() throws {
        #expect(try events("data: [DONE]\n\n").first?.data == "[DONE]")
    }

    @Test("Reassembles a payload split across chunk boundaries")
    func splitAcrossChunks() throws {
        var parser = SSEParser()
        #expect(try parser.consume(Array("data: hel".utf8)).isEmpty)
        #expect(try parser.consume(Array("lo\n".utf8)).isEmpty)
        let result = try parser.consume(Array("\n".utf8))
        #expect(result.first?.data == "hello")
    }

    @Test("Handles a CRLF terminator split across chunks")
    func splitCRLF() throws {
        var parser = SSEParser()
        // The trailing CR must wait for the next chunk to disambiguate CRLF.
        #expect(try parser.consume(Array("data: x\r".utf8)).isEmpty)
        let result = try parser.consume(Array("\n\r\n".utf8))
        #expect(result == [SSEEvent(type: "message", data: "x", id: nil, retry: nil)])
    }

    @Test("Reassembles a multi-byte UTF-8 scalar split across chunks")
    func splitUTF8Scalar() throws {
        var parser = SSEParser()
        var first = Data("data: ".utf8)
        let emoji = Array("😀".utf8) // F0 9F 98 80
        first.append(contentsOf: emoji[0..<2])
        #expect(try parser.consume(first).isEmpty)

        var second = Data(emoji[2..<4])
        second.append(contentsOf: Array("\n\n".utf8))
        let result = try parser.consume(second)
        #expect(result.first?.data == "😀")
    }

    @Test("Discards an incomplete event at end of stream")
    func incompleteEventNotDispatched() throws {
        var parser = SSEParser()
        #expect(try parser.consume(Array("data: partial".utf8)).isEmpty)
        // A later blank line completes it; without one, nothing is emitted.
        let result = try parser.consume(Array("\n\n".utf8))
        #expect(result.first?.data == "partial")
    }

    @Test("Throws when a single line exceeds the byte limit")
    func lineTooLong() {
        #expect(throws: SSEParser.Failure.self) {
            var parser = SSEParser(maxLineBytes: 8)
            _ = try parser.consume(Array("data: abcdefghijklmnop".utf8))
        }
    }

    @Test("Throws when accumulated event data exceeds the byte limit")
    func eventTooLarge() {
        #expect(throws: SSEParser.Failure.self) {
            var parser = SSEParser(maxEventBytes: 8)
            _ = try parser.consume(Array("data: aaaa\ndata: bbbb\ndata: cccc\n\n".utf8))
        }
    }
}
