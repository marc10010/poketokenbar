import Foundation
import PokeTokenBarCore

@MainActor
enum IngestTests: TestSuite {
    static let suiteName = "Ingest"

    static let tests: [(String, () throws -> Void)] = [
        ("transcript line with usage becomes an event", testTranscriptLineWithUsageBecomesAnEvent),
        ("transcript falls back to message id when there is no request i d", testTranscriptFallsBackToMessageIDWhenThereIsNoRequestID),
        ("lines without usable usage are ignored", testLinesWithoutUsableUsageAreIgnored),
        ("ingest server accepts wrapped and flat usage payloads", testIngestServerAcceptsWrappedAndFlatUsagePayloads),
        ("negative token counts are clamped", testNegativeTokenCountsAreClamped),
        ("http request parsing waits for the full body", testHTTPRequestParsingWaitsForTheFullBody),
        ("http request strips query string", testHTTPRequestStripsQueryString),
    ]

    static func testTranscriptLineWithUsageBecomesAnEvent() throws {
        let line = """
        {"type":"assistant","requestId":"req_abc","timestamp":"2026-09-08T10:11:12.345Z","message":{"id":"msg_01","model":"claude-opus-5","usage":{"input_tokens":120,"output_tokens":40,"cache_read_input_tokens":900}}}
        """
        let event = try unwrap(ClaudeCodeTranscriptSource.parseLine(Data(line.utf8), origin: "session.jsonl"))
        expectEqual(event.id, "cc:req_abc")
        expectEqual(event.inputTokens, 120)
        expectEqual(event.outputTokens, 40)
        expectEqual(event.cacheReadTokens, 900)
        expectEqual(event.model, "claude-opus-5")
        expectEqual(event.damage(countingCache: false), 160)
        expectEqual(event.damage(countingCache: true), 1_060)
    }

    static func testTranscriptFallsBackToMessageIDWhenThereIsNoRequestID() throws {
        let line = #"{"message":{"id":"msg_42","usage":{"input_tokens":1,"output_tokens":2}}}"#
        let event = try unwrap(ClaudeCodeTranscriptSource.parseLine(Data(line.utf8), origin: "x"))
        expectEqual(event.id, "cc:msg_42")
    }

    static func testLinesWithoutUsableUsageAreIgnored() {
        let noise = [
            #"{"type":"user","message":{"role":"user","content":"hola"}}"#,
            #"{"message":{"id":"m","usage":{"input_tokens":0,"output_tokens":0}}}"#,
            #"{"message":{"usage":{"input_tokens":5,"output_tokens":5}}}"#,
            "no soy json",
            "",
        ]
        for line in noise {
            expectNil(
                ClaudeCodeTranscriptSource.parseLine(Data(line.utf8), origin: "x"),
                "no debería emitir evento: \(line)"
            )
        }
    }

    static func testIngestServerAcceptsWrappedAndFlatUsagePayloads() throws {
        let wrapped = #"{"id":"req_1","model":"claude-opus-5","usage":{"input_tokens":10,"output_tokens":20}}"#
        let flat = #"{"input_tokens":7,"output_tokens":3}"#

        let first = try unwrap(IngestServer.event(from: Data(wrapped.utf8)))
        expectEqual(first.id, "ingest:req_1")
        expectEqual(first.damage(countingCache: false), 30)

        let second = try unwrap(IngestServer.event(from: Data(flat.utf8)))
        expectEqual(second.damage(countingCache: false), 10)
        expectTrue(second.id.hasPrefix("ingest:"), "sin id explícito generamos uno")

        expectNil(IngestServer.event(from: Data(#"{"foo":1}"#.utf8)))
        expectNil(IngestServer.event(from: Data("basura".utf8)))
    }

    static func testNegativeTokenCountsAreClamped() {
        let event = UsageEvent(id: "x", inputTokens: -10, outputTokens: 5)
        expectEqual(event.inputTokens, 0)
        expectEqual(event.damage(countingCache: false), 5)
    }

    static func testHTTPRequestParsingWaitsForTheFullBody() {
        let head = "POST /usage HTTP/1.1\r\nContent-Length: 18\r\n\r\n"
        expectNil(HTTPRequest(raw: Data(head.utf8)), "cuerpo incompleto: hay que seguir leyendo")

        let complete = head + #"{"input_tokens":1,"#
        let request = HTTPRequest(raw: Data(complete.utf8))
        expectEqual(request?.method, "POST")
        expectEqual(request?.path, "/usage")
        expectEqual(request?.body.count, 18)
    }

    static func testHTTPRequestStripsQueryString() {
        let raw = "GET /health?verbose=1 HTTP/1.1\r\nContent-Length: 0\r\n\r\n"
        expectEqual(HTTPRequest(raw: Data(raw.utf8))?.path, "/health")
    }
}
