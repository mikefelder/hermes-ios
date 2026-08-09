# Hermes for iPhone

A native SwiftUI client for a self-hosted [Nous Research Hermes Agent](https://github.com/NousResearch/hermes-agent). The app is designed for a Hermes instance running on Azure Container Apps and reachable from the iPhone over Tailscale.

Streaming chat, server-side sessions, Markdown rendering, capability discovery, and turn reconciliation are implemented and verified against a live deployment on a physical device. Approvals, automations, and push are not started.

## Product intent

This app is a way to reach one personal Hermes Agent from an iPhone. It is not a standalone product with its own model, memory, or conversation store.

**Hermes is authoritative.** Sessions, transcripts, tool execution, skills, memory, and configuration all live on the server and are shared by every client — the web dashboard, the terminal UI, and this app. A conversation started in the web UI can be continued on the phone and vice versa, because it is the same session object, not a copy.

That shapes the architecture:

- The app reads and writes server state rather than mirroring it. There is no local conversation database to drift, conflict, or need migrating.
- Features are discovered, not assumed. `GET /v1/capabilities` states what the deployment supports, and anything unsupported is disabled honestly rather than faked.
- Tools run on the Hermes host, never on the phone. Tool output is rendered as inert text and is never treated as an instruction or an approval.
- The only state that is genuinely local is what the server cannot hold: the connection profile, the Keychain secret, unsent drafts, and records of turns whose outcome is uncertain.

The deliberate trade is offline behaviour: without a local cache there is no transcript to read when the tailnet is unreachable. A read-through cache of recently viewed sessions can be added if that proves annoying in practice.

The user configures the server URL, username, and secret. The URL and username are stored as non-secret settings; the secret is stored in the iOS Keychain. Against a Hermes API server reached directly over a tailnet, that secret is the `API_SERVER_KEY` sent as a Bearer token. Against a deployment that fronts Hermes with a credential-validating proxy, it is the user's password and the proxy holds the key instead.

## Requirements

- Xcode 26.2 or newer
- iOS 26.2 deployment target
- A reachable Hermes Agent instance
- The Tailscale app, signed in to the same tailnet, when the server is published as a Tailscale Service

## Connecting to a Hermes server

The app talks to Hermes' OpenAI-compatible **API server**. That is a different surface from the Hermes web dashboard, and pointing the app at the dashboard is the most common setup mistake: the dashboard answers `/v1/...` with an HTML login redirect rather than JSON.

In the reference Azure deployment a Tailscale sidecar publishes both surfaces on one hostname:

| Port | Surface | Credentials |
| --- | --- | --- |
| `443` | Web dashboard (browser only) | Username + password |
| `8443` | OpenAI-compatible API server | API key as a Bearer token |

The API server exposes more than chat. `GET /v1/capabilities` advertises what a given build supports; the reference deployment offers Chat Completions, the Responses API, session resources, run approvals, tool progress events, and skills, all behind the same bearer key.

A turn uses the richest protocol the server supports:

| Protocol | Used when | Behaviour |
| --- | --- | --- |
| `POST /api/sessions/{id}/chat/stream` | A session is open and sessions are supported | Server owns the transcript; only the new message is sent |
| `POST /v1/responses` | No session bound, Responses supported | Server-side continuity through `previous_response_id` |
| `POST /v1/chat/completions` | Universal fallback | Stateless; the full transcript is resent each turn |

Configure the app with:

- **Server URL** — `https://hermes.<tailnet>.ts.net:8443`, including the port
- **Username** — left blank, which is what selects Bearer authentication
- **API key** — the Hermes `API_SERVER_KEY`, stored only in the iPhone Keychain

A deployment that puts a username/password-validating proxy in front of Hermes is also supported: enter the username and password, and the app sends HTTP Basic instead.

To check what a host actually serves before configuring the app, run the bundled probe. It reports status, content type, redirects, and a short body preview, and states whether you reached the API server or the dashboard:

```bash
scripts/probe-hermes.sh --url https://hermes.example.ts.net:8443 --key "$HERMES_API_KEY"
```

## Features

- First launch presents Hermes-styled connection onboarding.
- The user enters an editable agent name, HTTPS server URL, username, and secret (a password or an API key).
- Saving is disabled until those exact settings pass a connection test.
- Existing users can edit, retest, and save connection settings from Settings.
- A blank secret while editing preserves the existing Keychain credential, so clear it deliberately when switching a profile between password and API-key authentication.
- Proposed credentials are tested before replacing a working profile.
- Forget Server removes the profile metadata and its Keychain secret.
- The app shows connection state and discovered chat/mobile-adapter capabilities.
- Chat streams an assistant turn token by token, with a live transcript, a control that disconnects the stream while keeping partial text, and a new-conversation action.
- Sessions lists the agent's own sessions whatever created them — web dashboard, terminal UI, or this app — with source, message count, and tool-call count. Opening one loads its transcript and continues it.
- Assistant Markdown renders headings, lists, quotes, tables, links, and fenced code with copy and horizontal scrolling. Tool calls and tool output appear as inert fenced blocks.
- The running tool is named while it works.
- A dropped turn is reconciled against the server rather than resent; a resend is offered only when the turn provably never started.
- Automations remains a milestone placeholder.
- App content is covered whenever the scene is inactive to reduce app-switcher exposure.
- Four brand app icons ship in the asset catalog (Orbital Seal is the default; Luminous Agent, Orbital Engraved, and Signal Mark are alternates), switchable at runtime in Settings → Appearance → App Icon. Source masters live in `design/app-icons/` outside the app bundle.

## Architecture and security

- `AppEnvironment` owns protocol-backed settings, credential, connection-test, and logging dependencies.
- `AppModel` restores and transactionally updates the active server profile.
- `ServerProfile` normalizes host casing and trailing slashes while preserving ports and reverse-proxy path prefixes.
- Production configuration requires HTTPS and rejects URLs containing embedded credentials, queries, or fragments.
- Authentication supports HTTP Basic (username + password) and Bearer API keys, selected by whether a username is present. Basic usernames containing `:` are rejected to avoid ambiguous encoding.
- The connection test reads the server's `WWW-Authenticate` challenge and reports whether the server expects an API key or a username/password.
- Passwords use a generic-password Keychain item with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and never enter `ServerProfile` or `UserDefaults`.
- Connection requests use an ephemeral `URLSession` with no cookies, credential storage, or cache.
- Same-host HTTPS redirects are followed (common behind reverse proxies and Tailscale front ends); redirects that change host or downgrade to HTTP are rejected so the `Authorization` header is never sent to another origin. Endpoint construction stays within the configured HTTPS origin.
- Connection testing probes `GET /health`, authenticated `GET /v1/models`, and `GET /v1/capabilities`.
- Capabilities are discovered from the server, persisted, and refreshed on launch. They select the chat protocol and gate every optional feature; an unknown server degrades to chat only.
- `HermesEndpoint` is the single implementation of endpoint construction and the same-origin rule, shared by every client.
- Chat streaming rejects a response whose final URL left the configured origin before reading any of its body, and a generation guard prevents a cancelled turn from appending to a newer one.
- `ChatTurnCoordinator` owns one foreground stream per conversation and tracks acceptance, so a dropped turn is reconciled against the server transcript instead of being blindly resent.
- Assistant text and tool output are display content only; neither is treated as structured metadata or as an approval.
- Errors distinguish invalid configuration, offline, timeout, TLS, unauthorized, forbidden, unavailable, incompatible response, redirect, and cancellation states.
- `ServerProfile` is explicitly nonisolated so its `Codable` conformance remains safe from persistence actors under Swift 6 isolation rules.

## Project layout

```text
Hermes/
├── App/
│   ├── AppEnvironment.swift       # production dependency composition
│   ├── AppModel.swift             # active profile/capability/application state
│   └── RootView.swift             # restore gate, tabs, placeholders, privacy cover
├── DesignSystem/
│   ├── HermesTheme.swift          # colors, spacing, card/screen modifiers
│   └── Components/ConnectionStatusPill.swift
├── Domain/
│   ├── Chat/ChatModels.swift      # chat and agent event models
│   └── Connection/                # profile, capabilities, checks, errors, interpreters
├── Features/
│   ├── Chat/                     # turn coordinator, conversation, chat screen, Markdown views
│   ├── Connection/               # connection editor model and form
│   ├── Onboarding/WelcomeView.swift
│   ├── Sessions/                 # server session list
│   └── Settings/                 # settings screen and app-icon picker
├── Infrastructure/
│   ├── API/                      # SSE parser and the three stream decoders
│   ├── Auth/CredentialStore.swift
│   ├── Logging/HermesLogger.swift
│   ├── Networking/               # HTTP, chat streaming, sessions, capabilities
│   └── Persistence/ConnectionSettingsStore.swift
├── ContentView.swift              # compatibility wrapper/preview entry
└── HermesApp.swift                # app entry and root dependency state

HermesTests/                       # nine Swift Testing suites
scripts/probe-hermes.sh            # endpoint discovery helper
design/app-icons/                  # icon source masters, outside the app bundle
docs/                              # product and engineering specifications
```

Xcode uses file-system-synchronized groups, so empty-looking `PBXSourcesBuildPhase` arrays in `project.pbxproj` are expected. Do not manually add each Swift file to those arrays.

## Build and test

The unit tests cover URL normalization and unsafe-URL rejection, authorization header construction, redirect policy, health and model-list interpretation, SSE parsing, chat event decoding, response previews, and Keychain credential round-tripping.

```bash
xcodebuild test \
  -project Hermes.xcodeproj \
  -scheme Hermes \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Additional checks used before a release checkpoint:

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

## Development notes

- `Hermes.xcodeproj/project.pbxproj` contains the `HermesTests` target. Its `buildConfigurationList` must remain `AA100000000000000000000B`; an interrupted edit previously produced an invalid 25-character reference and caused empty test settings.
- The deployment target is intentionally iOS 26.2 because that SDK is installed. Lowering it remains an open product decision, not a build repair.
- The physical target runs the iOS 27 public beta, but the deployment target remains iOS 26.2. Do not raise it merely to run on iOS 27; an iOS 26.2-targeted app remains compatible unless it adopts iOS 27-only APIs.
- `xcode-select -p` points at stable `/Applications/Xcode.app/Contents/Developer`. Prefix Beta command-line builds with `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` rather than changing the global selection.
- Xcode 27 Beta's Swift 6.4 compiler crashed on the async Objective-C thunk for `URLSessionTaskDelegate` redirect handling. `HermesHTTPClient` uses the equivalent completion-handler callback instead.
- Xcode 27 rejects actor initialization with a non-Sendable `UserDefaults` parameter. `ConnectionSettingsStore` is a small `@unchecked Sendable` final class; its async protocol boundary and persistence behavior are unchanged.
- Documentation lives only in the root `docs/` tree. A former `Hermes/docs/` copy was removed because the app target's file-synchronized group shipped it inside the app bundle.
- The app currently forces dark appearance in `HermesApp.swift`.
- No external Swift packages are installed.
- No real credentials, hostnames, API keys, APNs keys, or production fixtures are committed.

## Roadmap

Chat, sessions, Markdown, capability discovery, and turn reconciliation are in
place. The next work is claiming more of what the server already offers:
explicit session creation so every conversation appears in Sessions, run
approvals for dangerous commands, session management (rename, delete, fork), and
a per-session model picker.

Known gaps:

- A new conversation is not bound to a session until one is opened, so it appears
  in Sessions only after Hermes creates it implicitly.
- Approvals and clarifications are not implemented, though the server advertises
  `run_approval_response` and `approval_events`.
- Drafts and uncertain-turn records are not persisted, so an app kill during a
  turn loses the reconciliation marker.
- Sessions and transcripts are not paginated; the list and history are capped.
- Reasoning content returned by the server is not displayed.
- No offline reading: without a cache there is no transcript when the tailnet is
  unreachable. This is a deliberate trade, revisitable as a read-through cache.
- Connection probing has no injected `URLProtocol`/mock transport tests, and the
  staged test includes no streaming framing probe.
- Network path and protected-data availability are not observed.
- No `HermesUITests` target, local mock server, CI workflow, `.xcconfig`, or
  string catalog.
- No APNs relay.

The specifications under `docs/` predate the discovery that the API server
exposes session resources, approvals, and capability discovery. They still
describe a `/mobile/v1` companion adapter as required for sessions, and a
SwiftData cache as the persistence strategy. Both assumptions are superseded by
this README; the documents will be reconciled as those areas are implemented.

Acceptance criteria and later milestones are in the [Delivery plan](docs/DELIVERY_PLAN.md).

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

## Upstream Hermes capabilities

Hermes documents these capabilities, which the app surfaces progressively:

- OpenAI-compatible Chat Completions and Responses APIs with SSE streaming.
- Persistent sessions, lineage, full-text search, usage metrics, and context compression.
- Structured tool calls, tool output, terminal/file tools, browser/search, image generation, and TTS.
- Skills, self-improving memory, profiles/personality, model selection, and reasoning controls.
- Background sessions and isolated delegated agents.
- Cron jobs and automation blueprints with delivery targets.
- Images, files, voice messages, reactions, typing state, and interactive approval/clarify prompts on capable gateway surfaces.
- A separate management dashboard API for sessions, skills, files, cron, models, status, and administration.

Dashboard APIs are internal upstream interfaces and may change. The app therefore uses capability discovery and adapters instead of assuming that every installed Hermes release exposes every management endpoint.

## Deployment shape

The reference deployment publishes both Hermes surfaces through one Tailscale Service. `tailscale serve` is a pass-through reverse proxy and does not rewrite credentials:

```text
iPhone app
  | HTTPS over active Tailscale tunnel
  | Authorization: Bearer <API_SERVER_KEY>
  v
Tailscale Service :8443 (pass-through)
  v
Hermes API server on 127.0.0.1:8642

Browser
  | HTTPS over the same tunnel, Basic Auth
  v
Tailscale Service :443 -> Hermes web dashboard

Hermes completion/webhook
  | signed event; no Hermes credentials
  v
Public Azure Push Relay
  | APNs token authentication
  v
Apple Push Notification service -> iPhone
```

A credential-translating edge that accepts Basic Auth and injects the bearer key upstream is also supported, and keeps the key off the phone entirely. The app uses the same fields either way.

Direct chat remains private to the tailnet. Only minimal notification metadata reaches the public relay; notification previews default to generic text.

## Implementation principles

- Native SwiftUI, Foundation networking, Swift Concurrency, Keychain, UserNotifications, and AVFoundation.
- Hermes is the source of truth. Local storage covers only what the server cannot hold.
- Chat correctness before broad administration features.
- No private API keys in source control, `UserDefaults`, logs, analytics, crash reports, or notification payloads.
- HTTPS required outside explicit debug builds; never bypass certificate validation.
- Local data is a cache. Hermes remains the source of truth for sessions and agent state.
- Destructive and high-impact remote actions always require clear confirmation.
- Every upstream feature is capability-gated and degrades to an understandable unavailable state.

## Project facts

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

Pin the deployed Hermes release during implementation and update the compatibility matrix before shipping.
