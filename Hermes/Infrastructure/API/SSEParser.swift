import Foundation

/// A decoded Server-Sent Event.
nonisolated struct SSEEvent: Equatable, Sendable {
    /// The event type from an `event:` field, or `"message"` when unspecified.
    var type: String
    /// The event payload from one or more `data:` fields, joined with `"\n"`.
    var data: String
    /// The most recent `id:` value in effect for this event, if any.
    var id: String?
    /// The reconnection hint from a `retry:` field in milliseconds, if any.
    var retry: Int?
}

/// An incremental parser for the `text/event-stream` wire format.
///
/// Bytes are fed in arbitrary chunks via ``consume(_:)`` as they arrive from the
/// network. The parser is byte-accurate at line boundaries, so multi-byte UTF-8
/// scalars split across chunks are reassembled correctly. It follows the WHATWG
/// event-stream rules relevant to Hermes:
///
/// - `LF`, `CR`, and `CRLF` all terminate a line.
/// - Lines beginning with `:` are comments (used for heartbeats) and are ignored.
/// - `data:` fields accumulate and are joined with `"\n"` on dispatch.
/// - A blank line dispatches the pending event only when it carried data.
/// - Unknown fields are ignored rather than failing the stream.
/// - An incomplete event at end-of-stream is discarded, never dispatched.
///
/// Bounded buffers guard against unterminated or oversized input.
nonisolated struct SSEParser {
    enum Failure: Error, Equatable {
        /// A single line exceeded ``maxLineBytes`` before a terminator arrived.
        case lineTooLong(Int)
        /// A single event's accumulated data exceeded ``maxEventBytes``.
        case eventTooLarge(Int)
    }

    private let maxLineBytes: Int
    private let maxEventBytes: Int

    private var buffer: [UInt8] = []
    private var dataLines: [String] = []
    private var eventType: String?
    private var pendingID: String?
    private var pendingRetry: Int?
    private var lastEventID: String?
    private var eventBytes = 0

    init(maxLineBytes: Int = 1 << 20, maxEventBytes: Int = 8 << 20) {
        self.maxLineBytes = maxLineBytes
        self.maxEventBytes = maxEventBytes
    }

    /// Feed a chunk of bytes and return any events completed by this chunk.
    mutating func consume<Bytes: Sequence>(_ incoming: Bytes) throws -> [SSEEvent]
    where Bytes.Element == UInt8 {
        buffer.append(contentsOf: incoming)

        var events: [SSEEvent] = []
        var lineStart = 0
        var i = 0

        while i < buffer.count {
            let byte = buffer[i]
            if byte == 0x0A { // LF
                try handleLine(Array(buffer[lineStart..<i]), into: &events)
                i += 1
                lineStart = i
            } else if byte == 0x0D { // CR
                if i == buffer.count - 1 {
                    // Possible CRLF split across chunks; wait for more bytes.
                    break
                }
                let line = Array(buffer[lineStart..<i])
                i += (buffer[i + 1] == 0x0A) ? 2 : 1
                try handleLine(line, into: &events)
                lineStart = i
            } else {
                i += 1
                if i - lineStart > maxLineBytes {
                    throw Failure.lineTooLong(i - lineStart)
                }
            }
        }

        if lineStart > 0 {
            buffer.removeFirst(lineStart)
        }
        return events
    }

    private mutating func handleLine(_ raw: [UInt8], into events: inout [SSEEvent]) throws {
        // Blank line: dispatch the pending event if it accumulated data.
        if raw.isEmpty {
            flush(into: &events)
            return
        }
        // Comment line.
        if raw[0] == 0x3A { // ':'
            return
        }

        let line = String(decoding: raw, as: UTF8.self)
        let (field, value) = Self.splitField(line)

        switch field {
        case "event":
            eventType = value
        case "data":
            dataLines.append(value)
            eventBytes += value.utf8.count + 1
            if eventBytes > maxEventBytes {
                throw Failure.eventTooLarge(eventBytes)
            }
        case "id":
            // Per the event-stream spec, ids containing NUL are ignored.
            if !value.contains("\u{0}") {
                pendingID = value
                lastEventID = value
            }
        case "retry":
            if let milliseconds = Int(value), milliseconds >= 0 {
                pendingRetry = milliseconds
            }
        default:
            break // Ignore unknown fields.
        }
    }

    private mutating func flush(into events: inout [SSEEvent]) {
        defer { resetPending() }
        guard !dataLines.isEmpty else { return }
        events.append(
            SSEEvent(
                type: eventType ?? "message",
                data: dataLines.joined(separator: "\n"),
                id: pendingID ?? lastEventID,
                retry: pendingRetry
            )
        )
    }

    private mutating func resetPending() {
        dataLines.removeAll(keepingCapacity: true)
        eventType = nil
        pendingID = nil
        pendingRetry = nil
        eventBytes = 0
    }

    private static func splitField(_ line: String) -> (field: String, value: String) {
        guard let colon = line.firstIndex(of: ":") else {
            return (line, "")
        }
        let field = String(line[line.startIndex..<colon])
        var valueStart = line.index(after: colon)
        if valueStart < line.endIndex, line[valueStart] == " " {
            valueStart = line.index(after: valueStart)
        }
        return (field, String(line[valueStart..<line.endIndex]))
    }
}
