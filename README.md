# Hermes for iPhone

A native SwiftUI companion for a self-hosted [Nous Research Hermes Agent](https://github.com/NousResearch/hermes-agent). The app is designed for a Hermes instance running on Azure and reachable from the iPhone over Tailscale.

> **Development status (August 6, 2026):** the secure app foundation and connection-settings vertical slice are implemented and verified. Reliable streamed chat is the next milestone. See [Development handoff](#development-handoff) for the exact resume point.

## Development handoff

This section is the source of truth for resuming work in a new development session.

### Current milestone state

| Area | State | Notes |
| --- | --- | --- |
| Product/engineering specifications | Complete | Eight detailed specifications are available under `docs/` and duplicated under `Hermes/docs/`; resolve that duplication before committing. |
| Phase 0 deployment discovery | External work pending | Deployed Hermes version, Azure edge behavior, sanitized API fixtures, and final adapter decision are not yet recorded. |
| Phase 1 app foundation | Substantially complete | App shell, dependency environment, design tokens, navigation, privacy cover, logging wrapper, unit-test target, and shared scheme are implemented. CI, `.xcconfig`, string catalog, UI-test target, and local mock server remain. |
| Phase 2 secure connection | Core vertical slice complete | Editable profile, HTTPS validation, Keychain password, Basic Auth client, staged connection test, capability snapshot, onboarding, settings, and forget flow are implemented. Network-path/protected-data awareness and deterministic network contract tests remain. |
| Phase 3 reliable chat | Not started | This is the next primary implementation milestone. |
| Phases 4–9 | Not started | Companion adapter, sessions, interactions, media, automations, push, and release hardening follow stable chat. |

### Implemented user experience

- First launch presents Hermes-styled connection onboarding.
- The user enters an editable agent name, HTTPS server URL, username, and password.
- Saving is disabled until those exact settings pass a connection test.
- Existing users can edit, retest, and save connection settings from Settings.
- A blank password while editing preserves the existing Keychain credential.
- Proposed credentials are tested before replacing a working profile.
- Forget Server removes the profile metadata and its Keychain password.
- The app shows connection state and discovered chat/mobile-adapter capabilities.
- Chat, Sessions, Automations, and Settings tabs are present; only Settings and connection onboarding are functional. The other product areas intentionally contain milestone placeholders.
- App content is covered whenever the scene is inactive to reduce app-switcher exposure.
- Four brand app icons ship in the asset catalog (Orbital Seal is the default; Luminous Agent, Orbital Engraved, and Signal Mark are alternates), switchable at runtime in Settings → Appearance → App Icon. Source masters live in `design/app-icons/` outside the app bundle.

### Implemented architecture and security

- `AppEnvironment` owns protocol-backed settings, credential, connection-test, and logging dependencies.
- `AppModel` restores and transactionally updates the active server profile.
- `ServerProfile` normalizes host casing and trailing slashes while preserving ports and reverse-proxy path prefixes.
- Production configuration requires HTTPS and rejects URLs containing embedded credentials, queries, or fragments.
- Authentication supports HTTP Basic (username + password) and Bearer API keys: a blank username sends the secret as a Bearer `API_SERVER_KEY`, which is how a Hermes API server reached directly over Tailscale expects to be called. Basic usernames containing `:` are rejected to avoid ambiguous encoding.
- The server URL must point at the API server, not the web dashboard. In the reference Azure deployment the Tailscale Service publishes the dashboard on `443` and the API server on `8443`, so the base URL is `https://hermes.<tailnet>.ts.net:8443` with a blank username. Port `443` returns the dashboard login redirect for `/v1/...`.
- The connection test reads the server's `WWW-Authenticate` challenge and reports whether the server expects an API key or a username/password.
- Passwords use a generic-password Keychain item with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and never enter `ServerProfile` or `UserDefaults`.
- Connection requests use an ephemeral `URLSession` with no cookies, credential storage, or cache.
- Same-host HTTPS redirects are followed (common behind reverse proxies and Tailscale front ends); redirects that change host or downgrade to HTTP are rejected so the `Authorization` header is never sent to another origin. Endpoint construction stays within the configured HTTPS origin.
- Connection testing currently probes `GET /health`, authenticated `GET /v1/models`, and optional `GET /mobile/v1/capabilities`.
- Errors distinguish invalid configuration, offline, timeout, TLS, unauthorized, forbidden, unavailable, incompatible response, redirect, and cancellation states.
- `ServerProfile` is explicitly nonisolated so its `Codable` conformance remains safe from persistence actors under Swift 6 isolation rules.

### Current source map

```text
Hermes/
├── App/
│   ├── AppEnvironment.swift       # production dependency composition
│   ├── AppModel.swift             # active profile/capability/application state
│   └── RootView.swift             # restore gate, tabs, placeholders, privacy cover
├── DesignSystem/
│   ├── HermesTheme.swift          # colors, spacing, card/screen modifiers
│   └── Components/
│       └── ConnectionStatusPill.swift
├── Domain/Connection/
│   └── ConnectionModels.swift     # profile, capabilities, checks, connection errors
├── Features/
│   ├── Connection/
│   │   ├── ConnectionEditorModel.swift
│   │   └── ConnectionFormView.swift
│   ├── Onboarding/WelcomeView.swift
│   └── Settings/SettingsView.swift
├── Infrastructure/
│   ├── Auth/CredentialStore.swift
│   ├── Logging/HermesLogger.swift
│   ├── Networking/
│   │   ├── ConnectionTestService.swift
│   │   └── HermesHTTPClient.swift
│   └── Persistence/ConnectionSettingsStore.swift
├── ContentView.swift              # compatibility wrapper/preview entry
└── HermesApp.swift                # app entry and root dependency state

HermesTests/
└── ConnectionFoundationTests.swift

Hermes.xcodeproj/xcshareddata/xcschemes/
└── Hermes.xcscheme                # shared Build/Test/Run scheme
```

Xcode uses file-system-synchronized groups, so empty-looking `PBXSourcesBuildPhase` arrays in `project.pbxproj` are expected. Do not manually add each Swift file to those arrays.

### Verification baseline

The following checks passed on August 6, 2026 with Xcode 26.2 (build `17C52`) and the iOS 26.2 simulator SDK:

- Debug simulator build
- Clean Release simulator build
- Xcode static analysis
- Shared-scheme unit tests: **11/11 passed**
- Real simulator Keychain save, replace, load, delete, and idempotent delete
- Project-file and shared-scheme XML parsing
- Editor diagnostics and `git diff --check`
- Source-diff scan for hard-coded credentials

The test suite covers URL normalization and unsafe URL rejection, Basic Authentication encoding, profile persistence without password data, idempotent metadata deletion, and Keychain credential round-tripping.

Xcode 27.0 Beta (build `27A5228h`) is installed at `/Applications/Xcode-beta.app` with the iOS 27.0 device and simulator SDKs. A clean universal (`arm64` + `x86_64`) Debug simulator build and an arm64 `HermesTests` build-for-testing pass with that toolchain. Xcode 27 also recognizes the connected physical `Alpine iPhone` as a compatible destination.

The target iPhone runs the iOS 27 public beta. The app has not yet been installed, launched, or exercised on it, so physical iOS 27 behavior remains a required validation step. No concrete iOS 27 simulator is currently listed by the Beta toolchain; executable tests therefore still run on the installed iOS 26.2 simulator.

Run the verified checks from the repository root:

```bash
xcodebuild build \
  -project Hermes.xcodeproj \
  -scheme Hermes \
  -configuration Debug \
  -sdk iphonesimulator \
  -derivedDataPath /tmp/HermesDerivedData \
  CODE_SIGNING_ALLOWED=NO

xcodebuild test \
  -project Hermes.xcodeproj \
  -scheme Hermes \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' \
  -derivedDataPath /tmp/HermesDerivedData

xcodebuild clean build \
  -project Hermes.xcodeproj \
  -scheme Hermes \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/HermesReleaseDerivedData \
  CODE_SIGNING_ALLOWED=NO

xcodebuild analyze \
  -project Hermes.xcodeproj \
  -scheme Hermes \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/HermesAnalyzeDerivedData \
  CODE_SIGNING_ALLOWED=NO

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild clean build \
  -project Hermes.xcodeproj \
  -scheme Hermes \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/HermesXcode27DerivedData \
  CODE_SIGNING_ALLOWED=NO
```

Do not pass `CODE_SIGNING_ALLOWED=NO` to the Keychain-inclusive test command. An unsigned simulator host causes Security framework error `errSecMissingEntitlement (-34018)`. Normal simulator ad-hoc signing makes the Keychain test pass.

If a connected physical iPhone is locked, Xcode may repeatedly log failure to start `com.apple.mobile.notification_proxy`. This is unrelated to a test explicitly targeted at the simulator.

### Repository state and cautions

- The Phase 1/2 implementation and documentation were still uncommitted at the last verified handoff. Run `git status --short` before editing or committing.
- Documentation lives only in the root `docs/` tree that `README.md` links to. The former `Hermes/docs/` copy was removed because the app target's file-synchronized group shipped it inside the app bundle; the built `.app` now contains no Markdown.
- `Hermes.xcodeproj/project.pbxproj` contains the `HermesTests` target. Its `buildConfigurationList` must remain `AA100000000000000000000B`; an interrupted edit previously produced an invalid 25-character reference and caused empty test settings.
- The deployment target is intentionally iOS 26.2 because that SDK is installed. Lowering it remains an open product decision, not a build repair.
- The physical target runs iOS 27 public beta, but the deployment target remains iOS 26.2. Do not raise it merely to run on iOS 27; an iOS 26.2-targeted app remains compatible unless it adopts iOS 27-only APIs.
- `xcode-select -p` still points to stable `/Applications/Xcode.app/Contents/Developer`. Prefix Beta command-line builds with `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` rather than changing the global selection unless all local projects should use Beta.
- Xcode 27 Beta's Swift 6.4 compiler crashed on the async Objective-C thunk for `URLSessionTaskDelegate` redirect handling. `HermesHTTPClient` now uses the equivalent completion-handler callback and still rejects all redirects.
- Xcode 27 rejects actor initialization with a non-Sendable `UserDefaults` parameter. `ConnectionSettingsStore` is now a small `@unchecked Sendable` final class; its async protocol boundary and persistence behavior are unchanged.
- The app currently forces dark appearance in `HermesApp.swift`.
- No external Swift packages are installed.
- No real Azure/Hermes credentials, hostnames, API keys, APNs keys, or production fixtures are committed.

### Known gaps before chat can be called production-ready

- The streaming chat engine is implemented and unit-tested: a bounded incremental `SSEParser`, a tolerant `ChatCompletionsEventDecoder`, and `ChatModels`/`AgentEvent`.
- The streaming `HermesChatClient`, turn coordinator, transcript, composer, Markdown renderer, and draft/retry/reconciliation behavior do not exist yet.
- Connection probing has no injected `URLProtocol`/mock transport tests yet.
- The current staged test does not include a lightweight streaming framing probe.
- Network path and protected-data availability are not observed yet.
- Capabilities are retained in memory after a successful test but are not restored across launches.
- No `HermesUITests` target, local mock server, CI workflow, `.xcconfig`, or string catalog exists.
- No SwiftData conversation cache exists.
- No companion adapter or APNs relay has been implemented.
- The app has not yet been validated against the actual Azure/Tailscale deployment.
- The app has not yet been signed, installed, or runtime-tested on the physical iOS 27 public-beta target.

### Exact next development sequence

The streaming chat engine (`SSEParser`, `ChatCompletionsEventDecoder`, and `ChatModels`/`AgentEvent`) is now implemented and unit-tested. The immediate next task is the streaming `HermesChatClient` that wires an injectable HTTP transport through the parser and decoder into an `AsyncThrowingStream<AgentEvent>`.

1. Commit the verified foundation as a clean checkpoint. The duplicate `Hermes/docs/` tree has been removed; root `docs/` is canonical.
2. Unlock and trust the target iPhone, then perform a signed Debug install and smoke test on iOS 27.
3. Record the deployed Hermes release/commit and capture sanitized `/health`, `/v1/models`, and streaming Chat Completions fixtures through the real Azure/Tailscale edge.
4. Introduce an injectable HTTP transport and deterministic connection-test fixtures, including unauthorized, forbidden, TLS, malformed JSON, adapter-absent, and cancellation cases.
5. Implement a bounded incremental `SSEParser` with LF/CRLF, multiline `data:`, UTF-8 chunk splits, heartbeat, `[DONE]`, malformed input, and size-limit tests.
6. Add chat request/response DTOs and a typed OpenAI-compatible `HermesChatClient` for `POST /v1/chat/completions`.
7. Normalize transport output into stable chat/agent events without trusting inline tool-progress prose.
8. Implement a turn coordinator with generation guards, explicit local cancellation, acceptance tracking, and outcome-unknown handling that never automatically duplicates a remote turn.
9. Build the native chat timeline and multiline composer with local draft safety, send/stop/retry states, text selection, and accessible streaming announcements.
10. Add integration/UI/accessibility tests and run the first end-to-end streamed turn against staging.
11. Only after stable chat, decide and begin the `/mobile/v1` companion adapter required for sessions, structured approvals, automations, and push events.

The detailed acceptance criteria and later milestones remain in the [Delivery Plan](docs/DELIVERY_PLAN.md).

## Product intent

Hermes for iPhone is a chat-first remote control for one personal Hermes Agent. It should make the highest-value mobile workflows excellent: converse with the agent, follow streamed work, approve risky actions, inspect artifacts, resume sessions, launch background work, manage automations, and receive completion notifications.

The user configures the server URL, username, and password in the app. The URL and username are stored as non-secret settings; the password is stored in iOS Keychain. The recommended Azure edge validates those Basic Auth credentials and injects the server-side `API_SERVER_KEY` expected by Hermes. The Hermes API key is never stored in the app or push service.

## Documentation

| Document | Purpose |
| --- | --- |
| [Product specification](docs/PRODUCT_SPEC.md) | Goals, personas, journeys, complete feature catalog, scope, and acceptance criteria |
| [Technical architecture](docs/TECHNICAL_ARCHITECTURE.md) | Native app structure, state, networking, persistence, models, and lifecycle |
| [Hermes integration](docs/HERMES_INTEGRATION.md) | Verified API surfaces, compatibility strategy, Azure/Tailscale contract, and endpoint mapping |
| [Design system](docs/DESIGN_SYSTEM.md) | Hermes visual language, mobile information architecture, components, motion, and accessibility |
| [Security and privacy](docs/SECURITY_PRIVACY.md) | Threat model, credential handling, transport, permissions, logging, and privacy requirements |
| [Push notifications](docs/PUSH_NOTIFICATIONS.md) | APNs architecture, relay contract, registration, delivery, deep links, and failure modes |
| [Quality strategy](docs/QUALITY_STRATEGY.md) | Unit, integration, UI, accessibility, performance, security, and release validation |
| [Delivery plan](docs/DELIVERY_PLAN.md) | Milestones, work breakdown, exit criteria, risks, and decisions |

## Confirmed upstream capabilities

The August 6, 2026 Hermes sources document these relevant capabilities:

- OpenAI-compatible Chat Completions and Responses APIs with SSE streaming.
- Persistent sessions, lineage, full-text search, usage metrics, and context compression.
- Structured tool calls, tool output, terminal/file tools, browser/search, image generation, and TTS.
- Skills, self-improving memory, profiles/personality, model selection, and reasoning controls.
- Background sessions and isolated delegated agents.
- Cron jobs and automation blueprints with delivery targets.
- Images, files, voice messages, reactions, typing state, and interactive approval/clarify prompts on capable gateway surfaces.
- A separate management dashboard API for sessions, skills, files, cron, models, status, and administration.

Dashboard APIs are internal upstream interfaces and may change. The app therefore uses capability discovery and adapters instead of assuming that every installed Hermes release exposes every management endpoint.

## Recommended deployment shape

```text
iPhone app
  | HTTPS over active Tailscale tunnel
  | Basic Auth: user-configured username/password
  v
Azure edge proxy (tailnet-only)
  | validates Basic Auth
  | injects Authorization: Bearer <API_SERVER_KEY>
  v
Hermes gateway API server :8642

Hermes completion/webhook
  | signed event; no Hermes credentials
  v
Public Azure Push Relay
  | APNs token authentication
  v
Apple Push Notification service -> iPhone
```

Direct chat remains private to the tailnet. Only minimal notification metadata reaches the public relay; notification previews default to generic text.

## Implementation principles

- Native SwiftUI, Foundation networking, Swift Concurrency, Keychain, SwiftData, UserNotifications, and AVFoundation.
- Chat correctness before broad administration features.
- No private API keys in source control, `UserDefaults`, logs, analytics, crash reports, or notification payloads.
- HTTPS required outside explicit debug builds; never bypass certificate validation.
- Local data is a cache. Hermes remains the source of truth for sessions and agent state.
- Destructive and high-impact remote actions always require clear confirmation.
- Every upstream feature is capability-gated and degrades to an understandable unavailable state.

## Current project facts

- Project: `Hermes.xcodeproj`
- App target: `Hermes`
- Bundle identifier: `com.slashmike.Hermes`
- Current deployment target: iOS 26.2
- Physical target: `Alpine iPhone`, iOS 27 public beta
- Verified toolchains: Xcode 26.2 (`17C52`) and Xcode 27.0 Beta (`27A5228h`)
- Current device families: iPhone and iPad
- External dependencies: none
- Test target: `HermesTests` using Swift Testing; `HermesUITests` is not yet created

The minimum supported iOS version and whether iPad remains in the first release are open product decisions tracked in the [delivery plan](docs/DELIVERY_PLAN.md#18-open-decisions).

## Primary references

- [Hermes Agent repository](https://github.com/NousResearch/hermes-agent)
- [Hermes product page](https://hermes-agent.nousresearch.com/)
- [Open WebUI/API server guide](https://hermes-agent.nousresearch.com/docs/user-guide/messaging/open-webui)
- [Messaging gateway guide](https://hermes-agent.nousresearch.com/docs/user-guide/messaging)
- [CLI guide](https://hermes-agent.nousresearch.com/docs/user-guide/cli)
- [Voice mode guide](https://hermes-agent.nousresearch.com/docs/user-guide/features/voice-mode)

Research baseline: upstream `main` and official documentation as observed on August 6, 2026. Pin the deployed Hermes release during implementation and update the compatibility matrix before shipping.
