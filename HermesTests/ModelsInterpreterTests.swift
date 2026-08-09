import Foundation
import Testing
@testable import Hermes

@Suite("Models interpreter")
struct ModelsInterpreterTests {
    private func data(_ string: String) -> Data { Data(string.utf8) }

    @Test("Parses the OpenAI data array shape")
    func openAIShape() {
        let ids = ModelsInterpreter.modelIDs(from: data(#"{"object":"list","data":[{"id":"hermes-agent"},{"id":"aux"}]}"#))
        #expect(ids == ["hermes-agent", "aux"])
    }

    @Test("Parses a bare array of model objects")
    func bareArray() {
        #expect(ModelsInterpreter.modelIDs(from: data(#"[{"id":"hermes-agent"}]"#)) == ["hermes-agent"])
    }

    @Test("Parses an array of plain strings")
    func stringArray() {
        #expect(ModelsInterpreter.modelIDs(from: data(#"["model-a","model-b"]"#)) == ["model-a", "model-b"])
    }

    @Test("Parses alternate wrapper keys", arguments: ["models", "result", "results"])
    func alternateWrapperKeys(key: String) {
        let ids = ModelsInterpreter.modelIDs(from: data(#"{"\#(key)":[{"id":"hermes-agent"}]}"#))
        #expect(ids == ["hermes-agent"])
    }

    @Test("Falls back to name or model when id is absent")
    func alternateIdentifierKeys() {
        #expect(ModelsInterpreter.modelIDs(from: data(#"{"data":[{"name":"by-name"}]}"#)) == ["by-name"])
        #expect(ModelsInterpreter.modelIDs(from: data(#"{"data":[{"model":"by-model"}]}"#)) == ["by-model"])
        #expect(ModelsInterpreter.modelIDs(from: data(#"{"data":[{"model_name":"by-model-name"}]}"#)) == ["by-model-name"])
    }

    @Test("Ignores empty and whitespace identifiers")
    func ignoresEmpty() {
        #expect(ModelsInterpreter.modelIDs(from: data(#"{"data":[{"id":"  "},{"id":"real"}]}"#)) == ["real"])
    }

    @Test("Returns no ids for an empty data array but recognizes structured JSON")
    func emptyButStructured() {
        let payload = data(#"{"object":"list","data":[]}"#)
        #expect(ModelsInterpreter.modelIDs(from: payload).isEmpty)
        #expect(ModelsInterpreter.isStructuredJSON(payload))
    }

    @Test("Recognizes a JSON object or array as structured")
    func structuredDetection() {
        #expect(ModelsInterpreter.isStructuredJSON(data(#"{"anything":true}"#)))
        #expect(ModelsInterpreter.isStructuredJSON(data("[1,2,3]")))
    }

    @Test("Non-JSON bodies are neither models nor structured")
    func nonJSON() {
        #expect(ModelsInterpreter.modelIDs(from: data("<html>nope</html>")).isEmpty)
        #expect(ModelsInterpreter.isStructuredJSON(data("<html>nope</html>")) == false)
        #expect(ModelsInterpreter.isStructuredJSON(Data()) == false)
    }
}
