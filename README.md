# Hermes for iPhone

Hermes for iPhone is a native companion for your own [Hermes Agent](https://github.com/NousResearch/hermes-agent). Start a conversation at your desk, continue it from your phone, and approve sensitive commands when Hermes needs your attention.

<img src="docs/screenshots/connect.png" alt="The Hermes connection screen" width="280">

Hermes still runs on a machine you control. The iPhone app connects directly to it, so your sessions, tools, and agent configuration stay in one place instead of being copied into a separate mobile service.

> **Project status:** The app is working and under active development. Chat, shared sessions, Markdown, tool activity, connection recovery, and dangerous-command approvals have been tested against a live Hermes deployment on a physical iPhone. Automations and push notifications are still ahead.

## Before you start

You will need:

- A running Hermes Agent with its API server enabled and reachable from your phone
- The server's `API_SERVER_KEY`
- Xcode 26.2 or newer
- Tailscale on your iPhone if your Hermes server is private to a tailnet

There is no App Store build yet, so the app must be built and installed with Xcode.

If you do not have a server yet, [hermes-agent-azure](https://github.com/mikefelder/hermes-agent-azure) can deploy Hermes to Azure Container Apps behind a private Tailscale endpoint.

## Get connected

Clone the project and create your local signing configuration:

```bash
git clone <repository-url> Hermes
cd Hermes
cp Config/Local.xcconfig.example Config/Local.xcconfig
```

Set `HERMES_BUNDLE_ID` and `HERMES_DEVELOPMENT_TEAM` in `Config/Local.xcconfig`. Then open `Hermes.xcodeproj` in Xcode and run the app on your iPhone.

On first launch, enter:

- **Server URL:** the API server address, including its port, such as `https://hermes.example.ts.net:8443`
- **Username:** leave this blank for the standard API-key setup
- **API key:** your `API_SERVER_KEY`

Tap **Test connection**, then **Save**.

### A common connection mistake

The Hermes web dashboard and API server are different endpoints. They may use the same hostname, but they usually listen on different ports. If you point the app at the dashboard, it receives an HTML login page instead of an API response.

You can check an endpoint before adding it to the app:

```bash
scripts/probe-hermes.sh \
  --url https://hermes.example.ts.net:8443 \
  --key "$HERMES_API_KEY"
```

In the reference Azure deployment, the dashboard uses port `443` and the API server uses port `8443`.

## What works today

- Streamed chat with Markdown, tables, and copyable code blocks
- Shared sessions across the iPhone app, web dashboard, and terminal UI
- Live tool activity and completed tool results
- Dangerous-command approvals, including one-time and session-level choices
- Recovery after an interrupted connection without silently sending the same work twice
- Draft preservation when the app is closed
- Alternate app icons and a privacy cover in the app switcher

The app asks Hermes which capabilities it supports and adjusts accordingly. Newer servers can use the richer Runs API for approvals, while older servers fall back to compatible chat endpoints.

One intentional limitation is that there is no offline transcript cache. If the server cannot be reached, previous conversations are not available in the app.

## Privacy and security

The app connects directly to your Hermes server. It does not send conversations through a third-party service.

- API keys are stored in the iPhone Keychain with `ThisDeviceOnly` protection.
- HTTPS is required in production configuration.
- Redirects cannot change hosts or downgrade to HTTP.
- Prompts, responses, credentials, and server addresses are excluded from logs.
- Assistant text and tool output are display-only. They cannot turn themselves into approvals or actions.
- Markdown cannot run scripts or load remote images, and links open only after you tap them.

See [Security and privacy](docs/SECURITY_PRIVACY.md) for the complete threat model.

## What's next

The next stretch of work is focused on the parts of Hermes that are most useful away from a desk:

- Better session management, including explicit creation, rename, delete, and fork
- Per-session model selection
- Clarification prompts and richer reasoning display
- Pagination for long session lists and transcripts
- Push notifications and background-task handoff
- UI tests, CI, and broader connection-test coverage

The documents in `docs/` describe both the current app and its intended full feature set. Some of the older design assumptions are being updated as Hermes exposes more capabilities directly through its API.

## Development

The project targets iOS 26.2 and has no external Swift package dependencies. Simulator builds and tests do not need a development team; installing on a physical device does.

Run the test suite with:

```bash
xcodebuild test \
  -project Hermes.xcodeproj \
  -scheme Hermes \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Do not add `CODE_SIGNING_ALLOWED=NO` to this test command. The Keychain tests need the simulator host's normal ad hoc signature.

For a signing-free simulator build:

```bash
xcodebuild build \
  -project Hermes.xcodeproj \
  -scheme Hermes \
  -configuration Debug \
  -sdk iphonesimulator \
  -derivedDataPath /tmp/HermesDerivedData \
  CODE_SIGNING_ALLOWED=NO
```

The source is organized by responsibility:

```text
Hermes/
├── App/              App state and dependency composition
├── DesignSystem/     Theme and reusable UI components
├── Domain/           Chat and connection models
├── Features/         Chat, sessions, onboarding, and settings
└── Infrastructure/   API, auth, networking, logging, and persistence

HermesTests/          Swift Testing suites
scripts/              Connection and development helpers
docs/                 Product and engineering documentation
```

Xcode uses file-system-synchronized groups, so new Swift files normally do not need to be added manually to `project.pbxproj`.

## Read more

- [Product specification](docs/PRODUCT_SPEC.md): goals, journeys, features, and acceptance criteria
- [Technical architecture](docs/TECHNICAL_ARCHITECTURE.md): app structure, state, networking, and lifecycle
- [Hermes integration](docs/HERMES_INTEGRATION.md): APIs, authentication, Tailscale, and compatibility
- [Design system](docs/DESIGN_SYSTEM.md): visual language, components, motion, and accessibility
- [Security and privacy](docs/SECURITY_PRIVACY.md): threat model and credential handling
- [Push notifications](docs/PUSH_NOTIFICATIONS.md): planned APNs architecture
- [Quality strategy](docs/QUALITY_STRATEGY.md): testing and release validation
- [Delivery plan](docs/DELIVERY_PLAN.md): milestones, risks, and decisions

## Hermes references

- [Hermes Agent repository](https://github.com/NousResearch/hermes-agent)
- [Hermes product page](https://hermes-agent.nousresearch.com/)
- [API server guide](https://hermes-agent.nousresearch.com/docs/user-guide/messaging/open-webui)
- [Messaging gateway guide](https://hermes-agent.nousresearch.com/docs/user-guide/messaging)
- [CLI guide](https://hermes-agent.nousresearch.com/docs/user-guide/cli)