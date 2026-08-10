import Foundation

/// The API server's self-description from `GET /v1/capabilities`.
///
/// Discovery is preferred over probing: the server states which protocols and
/// resources it supports, so unknown builds degrade to chat only instead of
/// having features guessed at.
nonisolated struct HermesCapabilityDocument: Decodable, Sendable {
    struct Features: Decodable, Sendable {
        var chatCompletions: Bool?
        var chatCompletionsStreaming: Bool?
        var responsesAPI: Bool?
        var responsesStreaming: Bool?
        var sessionResources: Bool?
        var sessionChatStreaming: Bool?
        var runApprovalResponse: Bool?
        var runStop: Bool?
        var toolProgressEvents: Bool?
        var sessionContinuityHeader: String?

        enum CodingKeys: String, CodingKey {
            case chatCompletions = "chat_completions"
            case chatCompletionsStreaming = "chat_completions_streaming"
            case responsesAPI = "responses_api"
            case responsesStreaming = "responses_streaming"
            case sessionResources = "session_resources"
            case sessionChatStreaming = "session_chat_streaming"
            case runApprovalResponse = "run_approval_response"
            case runStop = "run_stop"
            case toolProgressEvents = "tool_progress_events"
            case sessionContinuityHeader = "session_continuity_header"
        }
    }

    var platform: String?
    var model: String?
    var features: Features?
}

extension ServerCapabilities {
    /// Merge a discovered capability document into a snapshot, keeping values that
    /// the document does not mention.
    func merging(_ document: HermesCapabilityDocument, version: String?, models: [String]) -> ServerCapabilities {
        let features = document.features
        var merged = self
        merged.supportsChatCompletions = features?.chatCompletionsStreaming
            ?? features?.chatCompletions
            ?? supportsChatCompletions
        merged.supportsResponses = (features?.responsesStreaming ?? features?.responsesAPI) ?? false
        merged.supportsSessions = features?.sessionResources ?? false
        merged.supportsRunApproval = features?.runApprovalResponse ?? false
        merged.supportsRunStop = features?.runStop ?? false
        merged.supportsToolProgress = features?.toolProgressEvents ?? false
        merged.sessionContinuityHeader = features?.sessionContinuityHeader
        merged.observedVersion = version ?? observedVersion
        merged.models = models.isEmpty ? (document.model.map { [$0] } ?? self.models) : models
        merged.checkedAt = .now
        return merged
    }
}
