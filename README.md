# Hermes for iPhone

A native SwiftUI companion for a self-hosted [Nous Research Hermes Agent](https://github.com/NousResearch/hermes-agent). The app is designed for a Hermes instance running on Azure and reachable from the iPhone over Tailscale.

Connection settings, the secure app foundation, and the streaming primitives are implemented. Reliable streamed chat is the next milestone; sessions, automations, media, and push are not started.

## Product intent

Hermes for iPhone is a chat-first remote control for one personal Hermes Agent. It should make the highest-value mobile workflows excellent: converse with the agent, follow streamed work, approve risky actions, inspect artifacts, resume sessions, launch background work, manage automations, and receive completion notifications.

The user configures the server URL, username, and secret in the app. The URL and username are stored as non-secret settings; the secret is stored in the iOS Keychain. Against a Hermes API server reached directly over a tailnet, that secret is the `API_SERVER_KEY` sent as a Bearer token. Against a deployment that fronts Hermes with a credential-validating proxy, it is the user's password and the proxy holds the key instead.

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
- Chat, Sessions, Automations, and Settings tabs are present; only Settings and connection onboarding are functional. The other product areas intentionally contain milestone placeholders.
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
- Connection testing currently probes `GET /health`, authenticated `GET /v1/models`, and optional `GET /mobile/v1/capabilities`.
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
│   ├── Connection/                # connection editor model and form
│   ├── Onboarding/WelcomeView.swift
│   └── Settings/                  # settings screen and app-icon picker
├── Infrastructure/
│   ├── API/                       # SSEParser, ChatCompletionsEventDecoder
│   ├── Auth/CredentialStore.swift
│   ├── Logging/HermesLogger.swift
│   ├── Networking/                # HTTP client, connection test, response preview
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

The streaming primitives (`SSEParser`, `ChatCompletionsEventDecoder`, `ChatModels`/`AgentEvent`) are implemented and unit-tested. The next task is a streaming `HermesChatClient` that wires an injectable HTTP transport through the parser and decoder into an `AsyncThrowingStream<AgentEvent>`, followed by a turn coordinator, transcript, and composer.

Known gaps:

- No streaming chat client, turn coordinator, transcript, composer, or Markdown renderer.
- Connection probing has no injected `URLProtocol`/mock transport tests, and the staged test includes no streaming framing probe.
- Network path and protected-data availability are not observed.
- Capabilities are held in memory after a successful test but not restored across launches.
- No `HermesUITests` target, local mock server, CI workflow, `.xcconfig`, or string catalog.
- No SwiftData conversation cache.
- No companion `/mobile/v1` adapter or APNs relay.
- The app has not been signed, installed, or runtime-tested on the physical iOS 27 target.

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

- Native SwiftUI, Foundation networking, Swift Concurrency, Keychain, SwiftData, UserNotifications, and AVFoundation.
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
