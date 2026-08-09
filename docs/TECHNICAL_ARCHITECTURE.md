# Technical Architecture

## 1. Architecture goals

- Native, testable SwiftUI application with minimal third-party dependencies.
- Clear separation between stable Hermes chat APIs and unstable dashboard-management APIs.
- One authoritative active-server context with server-scoped persistence.
- Correct handling of iOS foreground/background transitions and unreliable networks.
- No duplicate turns when send/stream outcomes are ambiguous.
- Capability-gated features and adapters for pinned Hermes versions.
- Security boundaries that are easy to audit.

## 2. Platform baseline

Current project settings target iOS 26.2 with Swift 5 language mode and Main Actor default isolation. Before implementation, choose the minimum supported iOS version. The proposed architecture uses:

- SwiftUI and Observation
- Swift Concurrency (`async/await`, actors, `AsyncSequence`)
- Foundation `URLSession`, SSE parsing, and WebSocket tasks
- SwiftData for local cache
- Security framework for Keychain
- UserNotifications for APNs
- AVFoundation, PhotosUI, UniformTypeIdentifiers, and QuickLook
- Network framework for path awareness
- OSLog with privacy annotations

Avoid adding packages until a concrete gap is proven. Markdown is the likely exception; evaluate a maintained renderer against security, accessibility, tables, and code blocks before adoption.

## 3. System context

```text
+---------------- iPhone process ----------------+
| SwiftUI Views                                  |
| Feature Stores / AppModel                      |
| Domain Services                                |
| Hermes Chat Client | Management Client         |
| URLSession/SSE/WS | Keychain | SwiftData       |
+-------------------+-----------------------------+
                    | HTTPS through Tailscale
                    v
          Azure authentication edge
                    |
                    v
    Hermes API server + optional dashboard adapter
                    |
          Hermes state/tools/gateway

APNs path is separate: Hermes -> signed webhook -> Azure relay -> APNs.
```

## 4. Architectural layers

### 4.1 App shell

Owns lifecycle, active server, dependency construction, tabs, deep links, scene privacy, notification routing, and global banners.

Primary types:

- `HermesApp`
- `AppModel`
- `AppEnvironment`
- `AppRoute`
- `ActiveServerController`
- `NotificationRouter`

### 4.2 Features

Each feature owns views, presentation state, and a small store/view model. Features depend on domain protocols, never concrete networking or Keychain implementations.

- Onboarding/Connection
- Chat
- Sessions
- Automations
- Skills/Toolsets
- Agent settings
- Artifacts
- Notifications
- Diagnostics

### 4.3 Domain

Value types and use cases independent of transport and SwiftUI:

- `ServerProfile`, `ServerCapabilities`, `ConnectionReport`
- `Conversation`, `Message`, `ContentPart`, `AgentEvent`, `TurnState`
- `ToolInvocation`, `ApprovalRequest`, `ClarificationRequest`
- `Artifact`, `RemoteFile`
- `AutomationJob`, `Schedule`, `DeliveryTarget`
- `Skill`, `Toolset`, `ModelDescriptor`, `AgentProfile`, `UsageSummary`

### 4.4 Data/infrastructure

- `ConnectionSettingsStore`
- `KeychainCredentialStore`
- `HermesChatClient`
- `HermesManagementClient`
- `HermesGatewayClient`
- `CapabilityDiscoveryService`
- `ConversationRepository`
- `AutomationRepository`
- `ArtifactDownloadService`
- `PushRegistrationService`
- SwiftData cache and migration code

## 5. Proposed source tree

```text
Hermes/
├── App/
│   ├── HermesApp.swift
│   ├── AppModel.swift
│   ├── AppEnvironment.swift
│   ├── AppRoute.swift
│   └── RootView.swift
├── DesignSystem/
│   ├── HermesTheme.swift
│   ├── HermesTypography.swift
│   ├── HermesSpacing.swift
│   └── Components/
├── Domain/
│   ├── Connection/
│   ├── Chat/
│   ├── Sessions/
│   ├── Automations/
│   ├── Agent/
│   └── Notifications/
├── Infrastructure/
│   ├── API/
│   │   ├── HermesChatClient.swift
│   │   ├── HermesManagementClient.swift
│   │   ├── HermesGatewayClient.swift
│   │   ├── SSEParser.swift
│   │   ├── ResponsesEventDecoder.swift
│   │   └── DTO/
│   ├── Auth/
│   │   ├── BasicAuthentication.swift
│   │   └── KeychainCredentialStore.swift
│   ├── Persistence/
│   ├── Notifications/
│   ├── Networking/
│   └── Logging/
├── Features/
│   ├── Onboarding/
│   ├── Chat/
│   ├── Sessions/
│   ├── Automations/
│   ├── Skills/
│   ├── AgentSettings/
│   ├── Artifacts/
│   ├── Settings/
│   └── Diagnostics/
├── Resources/
└── Assets.xcassets/

HermesTests/
├── Domain/
├── API/
├── Persistence/
├── Security/
└── Fixtures/

HermesUITests/
└── CriticalJourneys/

PushRelay/                    # optional sibling deployment unit
├── src/
├── tests/
├── infrastructure/
└── README.md
```

Xcode's file-system-synchronized group should discover files under `Hermes/`; test and relay targets still require explicit project/configuration work.

## 6. Dependency composition

`HermesApp` creates one `AppEnvironment` per process. Concrete dependencies are initialized once and injected through SwiftUI environment or explicit initializers.

```text
AppEnvironment
├── settingsStore
├── credentialStore
├── cacheContainer
├── clientFactory
├── capabilityService
├── notificationService
├── logger
└── clock/uuid providers for tests
```

Do not use global singletons for credentials, network clients, databases, or active server. Apple process-global APIs such as `UNUserNotificationCenter.current()` should be wrapped.

## 7. Concurrency model

- UI-facing feature stores are `@MainActor` and `@Observable`.
- `CredentialVault`, stream coordination, repositories, upload manager, and token registration are actors.
- A `ChatTurnCoordinator` actor owns exactly one foreground stream per conversation.
- Each stream receives a generation UUID; stale events from cancelled/replaced tasks are discarded.
- DTO decoding and Markdown preprocessing occur off the main actor where useful.
- UI delta application is throttled to roughly 30–60 ms batches to avoid re-rendering per token.
- Cancellation propagates from view/store to URLSession tasks; server cancellation is a separate explicit operation.

## 8. Server profile and credentials

```swift
struct ServerProfile: Identifiable, Codable, Sendable {
    let id: UUID
    var name: String
    var baseURL: URL
    var username: String
    var createdAt: Date
    var updatedAt: Date
}

struct ServerCredential: Sendable {
    let password: String
}
```

Rules:

- URL and username may be persisted in a small preferences file or `UserDefaults` keyed by profile ID.
- Password is a `kSecClassGenericPassword` Keychain item keyed by bundle ID + profile UUID.
- Prefer `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` for background push registration needs; if no credential use is needed in background, use `WhenUnlockedThisDeviceOnly`.
- Password is passed transiently to the HTTP auth layer and never copied into domain/cache models.
- Password field displays a placeholder indicating a saved secret, never the value.
- Proposed settings are tested in an isolated ephemeral session before committing.
- Changing active configuration tears down streams and network clients before switching cache namespaces.

## 9. Networking stack

### 9.1 Client split

```swift
protocol HermesChatAPI: Sendable {
    func health() async throws -> Health
    func models() async throws -> [ChatModel]
    func stream(_ request: ChatRequest) -> AsyncThrowingStream<AgentEvent, Error>
}

protocol HermesManagementAPI: Sendable {
    func status() async throws -> AgentStatus
    func sessions(_ page: PageRequest) async throws -> Page<ConversationSummary>
    func messages(sessionID: String) async throws -> [Message]
    // Capability-gated operations only.
}

protocol HermesInteractiveAPI: Sendable {
    func connect() async throws
    func createOrResumeSession(_ request: SessionRequest) async throws -> String
    func submitPrompt(_ request: PromptRequest) async throws
    func respond(to interaction: InteractionResponse) async throws
    func stop(sessionID: String) async throws
}
```

The concrete `HermesService` can aggregate these protocols, but feature code requests only what it needs.

### 9.2 URL construction

- Persist an origin/base path, not a hand-concatenated endpoint.
- Normalize trailing slash once.
- Preserve an intentional reverse-proxy path prefix.
- Resolve `/health`, `/v1/...`, and optional `/api/...` through an explicit endpoint builder.
- Never allow endpoint paths or server responses to change scheme/host silently.
- Redirects to a different host require rejection; same-origin redirects have a small bounded limit.

### 9.3 Authentication

The deployed Azure stack has no header-rewriting edge. The Tailscale sidecar runs `tailscale serve`, a pass-through reverse proxy, and publishes two separate surfaces on the same Service hostname:

| Port | Surface | Auth |
| --- | --- | --- |
| `443` | Hermes web dashboard | HTTP Basic (dashboard username + password) |
| `8443` | Hermes OpenAI-compatible API server (`127.0.0.1:8642`) | `Authorization: Bearer API_SERVER_KEY` |

The app therefore sends the bearer key directly to the API server and must be configured with the `:8443` base URL. A blank username selects Bearer; the key is stored only in the Keychain. Port `443` returns the dashboard login redirect for `/v1/...` and is not a valid API base URL.

A Basic-to-Bearer translating edge remains a supported alternative deployment: if one is introduced, the app keeps the same username/password fields and no client change is required.

`URLSessionDelegate` may answer HTTP Basic challenges for the configured protection space. Preemptive Basic headers may be used only for the configured origin to avoid redirect leakage. Authentication is never attached to artifact URLs on another origin unless explicitly signed and capability-approved.

### 9.4 Session configurations

- Foreground JSON/SSE: default session with waits-for-connectivity and bounded resource timeout.
- Connection tests: ephemeral session, no cookies/cache, short stage-specific timeouts.
- Downloads/uploads: background `URLSession` only where endpoint authentication and server semantics are compatible; otherwise foreground with explicit limitation.
- WebSockets: dedicated client with heartbeat, generation guard, exponential backoff, and auth-terminal close handling.

## 10. Streaming architecture

### 10.1 Preferred protocol

Use `POST /v1/responses` with `stream: true` where supported because it can expose structured `function_call` and `function_call_output` events plus server-side `previous_response_id` continuity.

Fallback: `POST /v1/chat/completions` with `stream: true`, full conversation history, and inline progress interpreted only as display text—not as trusted structured approvals.

Optional richer adapter: dashboard/gateway JSON-RPC over WebSocket for session creation, prompt submission, message deltas, approvals, and clarification. It must be version-pinned and capability-tested.

### 10.2 SSE parser requirements

- Accept CRLF and LF.
- Join multiple `data:` lines with newline.
- Ignore comments/heartbeats.
- Support `event`, `id`, and `retry` fields.
- Enforce maximum line/event/buffer sizes.
- Decode UTF-8 split across URLSession chunks.
- Recognize `[DONE]` only for protocols that define it.
- Preserve unknown event types for diagnostics without failing the stream.
- Never log raw event payloads in production.

### 10.3 Event normalization

Transport-specific events map into a stable internal enum:

```text
turnAccepted(serverTurnID)
messageStarted(messageID, role)
textDelta(messageID, text)
reasoningDelta(messageID, text)
toolStarted(invocation)
toolUpdated(invocationID, safePreview)
toolCompleted(invocationID, resultSummary)
approvalRequested(request)
clarificationRequested(request)
artifactAvailable(artifact)
usageUpdated(summary)
turnCompleted(result)
turnFailed(error)
unknown(type)
```

Views do not decode SSE/JSON-RPC DTOs.

### 10.4 Idempotency and ambiguous sends

Each user send receives a client UUID. If the server supports idempotency metadata, send it. Otherwise:

- Persist the outgoing turn as `sending` before network I/O.
- Mark `accepted` only after a response ID/session event/first valid stream event.
- If transport fails before acceptance, offer retry.
- If it fails after request bytes may have arrived but before acceptance, mark **Outcome unknown** and reconcile sessions before offering a new send.
- Never automatically replay a non-idempotent request after an ambiguous failure.
- On stream loss after acceptance, reconnect/resume if protocol supports it; otherwise fetch transcript/session state.

## 11. Capability discovery

`CapabilityDiscoveryService` runs after authentication and on version changes:

1. `GET /health` without exposing response details.
2. `GET /v1/models` with authenticated edge request.
3. Probe Responses API support using a non-executing or documented capability mechanism; avoid expensive chat probes when possible.
4. Probe management `GET /api/status` only when configured adapter supports its auth contract.
5. Read version and derive a feature set from an explicit compatibility table.
6. Optionally establish JSON-RPC and record announced methods/events.

Persist:

```text
serverProfileID
observedVersion
protocols: chatCompletions/responses/management/jsonRPC
feature flags
checkedAt
compatibilityAdapterVersion
```

Unknown versions default to stable chat only. Destructive management operations require exact tested compatibility.

## 12. Persistence

### 12.1 Source of truth

Hermes is authoritative for sessions, messages, automations, skills, and status. SwiftData is a cache for fast launch and offline reading.

### 12.2 Suggested models

- `CachedServer`
- `CachedConversation`
- `CachedMessage`
- `CachedContentPart`
- `CachedToolInvocation`
- `CachedArtifact`
- `CachedAutomationJob`
- `PendingDraft`
- `NotificationInboxItem`
- `CapabilitySnapshot`

All records include `serverProfileID`. Remote IDs are unique only within that namespace.

### 12.3 Cache policy

- Show cache immediately with a stale indicator when needed.
- Refresh active conversation on foreground and after deep links.
- Reconcile pages by remote ID and server update timestamp.
- Do not delete local data solely because a paginated response omitted it.
- Explicit remote deletion removes the cache after server success.
- Cache only artifact metadata; downloaded files live in a protected cache directory with size/age eviction.
- Provide per-server and all-data clearing.

### 12.4 Protection and migration

- Apply complete file protection to caches/downloads where compatible with required background behavior.
- Use schema versions and migration tests.
- If migration fails, preserve settings/Keychain, rebuild disposable server cache, and explain the reset.

## 13. Chat presentation architecture

`ChatStore` owns:

- selected conversation;
- loaded transcript and pagination;
- local draft and attachments;
- current turn state;
- connection/banner state;
- pending interaction;
- stream task identity.

Message rendering uses typed `ContentPart`s rather than one attributed string:

- text/Markdown
- code
- image
- file/audio
- tool call/result
- reasoning (if exposed)
- approval/clarification
- error/status

Long transcripts use lazy stacks and stable message IDs. Stream updates mutate only the active message model.

## 14. Attachments and artifacts

- Security-scope imported file URLs only for the duration needed.
- Copy selected content into an app-protected staging directory.
- Enforce configurable server-advertised and app hard limits.
- Compute MIME type from UTType and validate server response.
- Strip photo metadata by default when re-encoding camera/library images; let the user opt to preserve originals.
- Downloads use randomized local names plus separately stored display names.
- Quick Look receives only local, validated files.
- Sharing is user-initiated through system share sheet.

The exact upload request for chat attachments must be confirmed against the pinned adapter. The dashboard `/api/files/upload-stream` is a management upload, not automatically a chat attachment API.

## 15. Deep links

Internal URL shape:

```text
hermes://chat/<serverID>/<sessionID>
hermes://interaction/<serverID>/<interactionID>
hermes://automation/<serverID>/<jobID>
hermes://settings/connection
```

Universal links are optional. Notification payload IDs are untrusted input:

- validate format and size;
- resolve only within the active/payload server namespace;
- authenticate and refresh from server;
- never execute an action directly from a link;
- queue route until app setup/unlock is complete.

## 16. App lifecycle

### Foreground

- Refresh network path and credentials availability.
- Reconnect active stream/event channel if meaningful.
- Reconcile any uncertain turns.
- Process queued deep link.
- Refresh active transcript and actionable notification inbox.

### Background

- Stop UI-only timers and socket retry loops.
- Allow finite active request completion only under iOS background task budget.
- Persist draft/turn/cache state atomically.
- Do not claim the WebSocket remains connected.
- Rely on APNs for later completion/actionable events.

### Termination/relaunch

- Restore route only after credentials and cache are ready.
- Convert `sending`/`streaming` local records into `reconciling`, not `failed`.
- Query server before enabling retry.

## 17. Error model

Domain error categories:

- invalid configuration
- Tailscale/network unavailable
- DNS failure
- TLS failure
- edge authentication rejected
- Hermes authentication/upstream misconfigured
- forbidden/capability unavailable
- incompatible version
- timeout/cancelled
- rate limited
- provider/model/tool failure
- malformed response
- stream interrupted/outcome unknown
- server unavailable/cold start
- local storage/permission failure

Each maps to a stable user message, recovery actions, retry policy, and redacted diagnostic code. Raw server bodies appear only in an opt-in diagnostics detail after secret filtering.

## 18. Logging and observability

Use `Logger` categories: lifecycle, connection, api, stream, persistence, push, media, and security.

Allowed fields:

- operation name;
- generated correlation ID;
- status code/category;
- durations and byte counts;
- Hermes version/capability flags;
- redacted error code.

Never log:

- Authorization headers, password, API key, cookies, APNs token;
- prompts/responses/reasoning/tool arguments/results;
- attachment bytes or private file paths;
- raw server URL/hostname/username;
- notification body.

Diagnostics export replaces server IDs and session IDs with per-report aliases.

## 19. Build configuration

Create `.xcconfig` files for non-secret values:

- bundle identifiers per environment;
- push relay public base URL;
- APNs environment flags derived from entitlement/build;
- feature flags for experimental adapters;
- URL scheme.

Secrets are never committed or placed in build settings. APNs signing key stays in Azure secret storage. Hermes API key stays in the Azure edge secret store/environment.

## 20. Testing architecture

- Protocol-based dependency injection and deterministic clock/UUID/network fixtures.
- Custom `URLProtocol` for REST/SSE chunk tests.
- Local test WebSocket/SSE server for reconnect, framing, auth, and cancellation.
- In-memory SwiftData for repository tests.
- Fake Keychain wrapper for most tests plus device-level Keychain smoke test.
- Launch arguments for UI scenarios and accessibility states.

See [Quality Strategy](QUALITY_STRATEGY.md).

## 21. Architecture decisions to record

Create an ADR when deciding:

1. Minimum iOS and iPhone-only versus universal.
2. Markdown renderer dependency.
3. Stable chat-only API versus bundled Hermes companion adapter.
4. Management dashboard exposure/authentication contract.
5. Push relay implementation/runtime and event ingestion method.
6. Single profile v1 versus multiple server profiles.
7. SwiftData cache encryption/protection beyond Data Protection.
8. Voice: system dictation, server transcription, or both.
