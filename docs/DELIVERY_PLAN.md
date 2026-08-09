# Delivery Plan

## 1. Delivery strategy

Ship in vertical slices. First prove secure private connectivity and a correct streamed chat against the actual Azure deployment. Then add the mobile companion adapter for structured events and management, followed by sessions, interaction safety, artifacts, automations, push, and broader controls.

Do not build UI against assumed internal endpoints. Every phase that depends on dashboard or JSON-RPC behavior begins with a pinned-version contract fixture and capability definition.

## 2. Scope releases

### Engineering prototype

- Editable URL/username/password.
- Keychain storage.
- Tailscale/private HTTPS connection test.
- `/v1/models` and one streamed Chat Completions request.
- Basic Markdown/text rendering.
- No persistence, push, or management commitments.

### P0 internal alpha

- Production-quality onboarding/edit/forget flow.
- Stable chat client with SSE, draft safety, cancellation semantics, and reconciliation.
- Cached sessions/transcripts through a read-only adapter or clearly local chat continuity.
- Hermes design system and critical accessibility.
- Diagnostics and core automated tests.
- No accidental duplicate turns under tested failures.

### P1 full v1 beta

- Structured Responses/tool events.
- Rich companion adapter and capabilities.
- Approvals and clarification.
- Attachments/artifacts and voice input.
- Session search/resume/rename/delete/usage.
- Background tasks.
- Automations.
- Model/profile summary and safe model/personality/reasoning controls.
- Skills and toolsets.
- APNs completion/failure/action-required notifications.
- Full accessibility/security/performance/release validation.

### Post-v1

- Multi-server profiles.
- Full file browser/write operations.
- Skills Hub installs and memory management.
- Delegation graph, rollback, system operations.
- Live Activities/widgets/App Intents/watch companion.
- Rich encrypted notification previews.
- Broader iPad administration experience.

## 3. Relative sizing

Use relative engineering sizes because actual duration depends on the deployed Hermes version, adapter scope, Apple account readiness, and design assets.

- **S:** focused change with known contract.
- **M:** multi-file feature with tests and states.
- **L:** cross-layer feature or external integration.
- **XL:** new service/protocol with security and operations work.

A single experienced iOS engineer can execute the native work sequentially; the companion adapter/push relay benefit from parallel backend ownership. Treat estimates as planning aids, not dates.

## 4. Phase 0 — decisions and deployment discovery

**Outcome:** reproducible staging contract and approved architecture.

Tasks:

- [ ] Record deployed Hermes release/commit, profile, API server settings, host/ports, and gateway topology. (S)
- [ ] Confirm Azure proxy/runtime, Tailscale hostname, ACLs/grants, NSG/firewall, HTTPS certificate, and cold-start behavior. (M)
- [ ] Implement/verify user-facing Basic Auth at edge and server-side bearer injection. (M)
- [ ] Capture sanitized health/models/Chat Completions/Responses fixtures. (M)
- [ ] Decide whether management dashboard is enabled and how its authentication is configured. (S)
- [ ] Approve the `/mobile/v1` companion adapter recommendation for P1. (S)
- [ ] Decide minimum iOS and iPhone-only versus iPhone+iPad. (S)
- [ ] Confirm Apple Developer team, bundle identifier, APNs capability, and relay hosting subscription. (S)
- [ ] Create ADRs for open architecture decisions. (M)
- [ ] Create staging secrets and rotation/runbook; no production data in tests. (M)

Exit criteria:

- A command-line client can connect through Tailscale + HTTPS + Basic Auth and receive an authenticated streamed response.
- Direct Hermes ports are not publicly reachable.
- Versioned fixtures and a deployment diagram are reviewed.
- P0 and P1 API dependencies are marked stable, adapter-required, or deferred.

## 5. Phase 1 — project foundation and design system

**Outcome:** buildable/testable app shell with secure dependency boundaries.

Tasks:

- [ ] Reorganize generated app into `App`, `Domain`, `Infrastructure`, `Features`, `DesignSystem`, and `Resources`. (M)
- [ ] Add `HermesTests` and `HermesUITests` targets and shared test support. (M)
- [ ] Add Debug/Release `.xcconfig` files with no secrets. (S)
- [ ] Create `AppEnvironment`, `AppModel`, route model, and dependency protocols. (M)
- [ ] Add Hermes color/type/spacing assets and reusable component previews. (M)
- [ ] Build iPhone tab/navigation shell and privacy cover. (M)
- [ ] Add OSLog wrapper and redacted diagnostic error model. (S)
- [ ] Add string catalog/localization-ready copy. (S)
- [ ] Build local mock API/SSE/WebSocket harness and README. (L)
- [ ] Configure CI for build, unit tests, secret scan, and Markdown validation. (M)

Exit criteria:

- Simulator build/test succeeds from a clean checkout.
- Design tokens pass initial contrast/Dynamic Type review.
- Dependencies are injectable and production logs contain no content.
- Mock server can run healthy/auth/stream-drop scenarios.

## 6. Phase 2 — connection onboarding and secure settings

**Outcome:** user can safely configure, test, edit, and forget a server.

Tasks:

- [ ] Implement `ServerProfile` URL normalization/validation. (M)
- [ ] Implement Keychain credential actor and device-only accessibility policy. (M)
- [ ] Implement origin-bound Basic Auth and redirect handling. (M)
- [ ] Build staged `ConnectionTestService`. (L)
- [ ] Build welcome/setup UI, secure password semantics, test result rows, and Tailscale guidance. (L)
- [ ] Build Settings > Connection edit/test/save/forget flow. (M)
- [ ] Implement network-path and protected-data awareness. (M)
- [ ] Add connection status pill/banner and actionable error mapping. (M)
- [ ] Add capability snapshot model and initial `/health`/`/v1/models` discovery. (M)
- [ ] Test Keychain absence from preferences/container/logs with secret canaries. (M)

Exit criteria:

- Correct credentials connect; wrong proposed credentials do not overwrite working settings.
- Password persists only in Keychain and forget deletes all profile-local data.
- Cross-origin auth leakage and production HTTP are blocked by tests.
- Every connection-test stage has a useful failure state.

## 7. Phase 3 — reliable chat vertical slice

**Outcome:** production-quality text chat through the stable API-server surface.

Tasks:

- [ ] Implement endpoint builder and typed API-server client. (M)
- [ ] Implement bounded streaming SSE parser and Chat Completions decoder. (L)
- [ ] Implement Responses decoder behind capability flag. (L)
- [ ] Normalize transport into `AgentEvent`. (M)
- [ ] Implement `ChatTurnCoordinator` generation guards, cancellation, acceptance, uncertain-send, and reconciliation states. (L)
- [ ] Build chat timeline, message parts, Markdown/code/link safety, and text selection/copy. (L)
- [ ] Build multiline composer, local draft, send/error/retry, keyboard/safe-area behavior. (L)
- [ ] Implement tool-progress fallback as untrusted display content. (M)
- [ ] Implement stop remote work only where supported; distinguish local disconnect. (M)
- [ ] Add streaming throttling and long-transcript performance work. (M)
- [ ] Add background/foreground persistence and stream teardown/reconcile. (M)
- [ ] Complete chat unit/integration/UI/accessibility tests. (L)

Exit criteria:

- Chat streams correctly for all fixture chunk boundaries.
- Connection loss before/after acceptance never silently duplicates a turn.
- Cached draft survives relaunch/failure.
- 1,000-message and long-stream performance stays within agreed budgets.
- VoiceOver can configure, send, hear phase completion, and read response.

## 8. Phase 4 — companion adapter and capabilities

**Outcome:** stable mobile-specific access to rich Hermes behavior without exposing dashboard internals.

This is an **XL** backend workstream and the main P1 dependency.

Tasks:

- [ ] Create `PushRelay/` and/or `MobileAdapter/` deployment units after runtime decision. (M)
- [ ] Define `/mobile/v1` OpenAPI, semantic versions, scopes, idempotency, errors, and capabilities. (L)
- [ ] Implement edge identity propagation and least-privilege authorization. (L)
- [ ] Wrap pinned Hermes session/status/model/skills/toolsets/cron APIs. (XL)
- [ ] Wrap JSON-RPC/agent event stream or provide normalized adapter SSE/WebSocket. (XL)
- [ ] Implement short-lived single-use WebSocket tickets. (L)
- [ ] Implement structured approval/clarification and stop/redirect/queue/steer. (XL)
- [ ] Implement safe locked-root artifact/file streaming endpoints. (L)
- [ ] Add outbox/event IDs for push and client reconciliation. (L)
- [ ] Add adapter unit/contract/security tests and generated/sanitized fixtures. (XL)
- [ ] Deploy staging, instrument metadata-only health/metrics, and document rollback. (M)

Exit criteria:

- App discovers adapter/version/capabilities.
- Adapter supports exact staging Hermes release and fails safely on mismatch.
- Mutations are scoped, idempotent, confirmed, and contract-tested.
- Dashboard tokens/API keys never reach the app.
- Fuzz/path/auth/security tests have no critical/high findings.

If the adapter is not approved, reduce v1 scope to stable chat plus features achievable through documented `/v1` APIs; do not directly depend on dashboard internals for App Store release.

## 9. Phase 5 — sessions, structured activity, and interactions

**Outcome:** Hermes' agent workflow is preserved natively.

Tasks:

- [ ] Add SwiftData cache, server namespace, migrations, and cache policy. (L)
- [ ] Implement session pagination, detail/messages, source filters, and refresh. (L)
- [ ] Implement FTS session search and highlighted snippets. (M)
- [ ] Implement latest-descendant/resume and lineage presentation. (M)
- [ ] Implement rename/delete with rollback/confirmation. (M)
- [ ] Implement usage/context summary and model/profile metadata. (M)
- [ ] Render structured tool invocation lifecycle and bounded outputs. (L)
- [ ] Implement approval card and authenticated idempotent response. (L)
- [ ] Implement single/multi/free-form clarification. (L)
- [ ] Implement new/retry/undo/compress/title and slash-command picker where supported. (M)
- [ ] Implement busy input modes and background task launch/status. (L)
- [ ] Add comprehensive interaction/replay/expiry/accessibility tests. (L)

Exit criteria:

- Sessions reconcile correctly across restart/compression/other clients.
- Tool events update one stable card without transcript flooding.
- Wrong-server/session, duplicate, stale, and expired interaction responses are rejected.
- P0 cached/offline reading and P1 search/resume actions work.

## 10. Phase 6 — rich media, voice, and artifacts

**Outcome:** mobile-native input/output beyond text.

Tasks:

- [ ] Finalize chat attachment contract and advertised size/type limits. (M)
- [ ] Implement PhotosPicker, camera, file importer, protected staging, metadata stripping, and previews. (L)
- [ ] Implement upload progress/cancel/retry and server attachment mapping. (L)
- [ ] Implement artifact metadata, safe downloads, cache eviction, Quick Look, and share sheet. (L)
- [ ] Implement image/audio/PDF/text/code rendering states. (L)
- [ ] Implement composer dictation or voice-message recording based on ADR. (L)
- [ ] Implement audio interruption/background/permission handling. (M)
- [ ] Add TTS playback only if server emits a supported artifact/stream. (M/P2)
- [ ] Add malicious/oversized file and permission/accessibility tests. (L)

Exit criteria:

- Supported files round-trip without loading unbounded data into memory.
- No cross-origin credential forwarding or active-content execution.
- Permission denial/interruption leaves chat stable.
- Artifacts preview/share correctly on physical devices.

## 11. Phase 7 — automations and agent controls

**Outcome:** useful Hermes management without recreating the entire dashboard.

Tasks:

- [ ] Implement automation list/detail grouped by state/next run. (M)
- [ ] Implement create/edit validation for prompt/script/schedule/delivery/model/skills/toolsets/workdir. (L)
- [ ] Implement pause/resume/run/delete with idempotency and confirmations. (M)
- [ ] Display server/device timezones and last/next status/errors. (M)
- [ ] Add automation blueprints if stable. (M/P2)
- [ ] Implement configured model picker, session model, personality, and reasoning controls. (L)
- [ ] Implement skills list/detail/toggle. (M)
- [ ] Implement toolsets list/detail/toggle with remote execution warning. (M)
- [ ] Implement read-only memory/provider and gateway health status. (M)
- [ ] Add expensive/destructive/admin role and confirmation tests. (L)

Exit criteria:

- Automation operations match server state after refresh and survive duplicate taps.
- Script/no-agent/high-cost controls communicate impact.
- Controls disappear or become read-only when capability/scope is absent.
- Raw environment/config/provider secrets are not exposed.

## 12. Phase 8 — push relay and APNs

**Outcome:** secure notifications for work that finishes or needs input while app is suspended.

This is an **XL** cross-platform workstream.

Tasks:

- [ ] Choose Azure runtime/storage/queue and write infrastructure-as-code. (M)
- [ ] Create Apple APNs key/capability/environments and Key Vault secret. (M)
- [ ] Implement one-time pairing, device registration/update/revoke, and token encryption. (L)
- [ ] Implement signed event ingestion, replay protection, deduplication, TTL, and rate limits. (L)
- [ ] Implement APNs provider client, environment/topic routing, retries, and invalid-token cleanup. (L)
- [ ] Implement Hermes adapter event outbox and allowlisted event mapping. (L)
- [ ] Implement iOS permission education, registration, preferences, and repair flow. (L)
- [ ] Implement notification inbox, foreground deduplication, badges, and deep links. (L)
- [ ] Implement generic payloads and privacy controls; no direct approval action. (M)
- [ ] Add relay observability/alerts/runbook. (M)
- [ ] Complete physical-device development and TestFlight APNs matrix. (L)

Exit criteria:

- End-to-end completion/failure/approval/clarification notification works from staging Hermes to physical device.
- Relay contains no Hermes credentials or conversation content.
- Duplicate, replay, outage, token rotation, revoke, and Tailscale-off deep links behave correctly.
- Production APNs environment is validated through TestFlight.

## 13. Phase 9 — hardening and release

**Outcome:** releasable v1 with documented operations and rollback.

Tasks:

- [ ] Complete all P1 empty/loading/error/offline/background states. (L)
- [ ] Run full VoiceOver, Dynamic Type, contrast, Reduce Motion/Transparency, Voice/Switch Control checks. (L)
- [ ] Profile launch, long chat, streaming, uploads, database, memory, energy, and reconnect loops. (L)
- [ ] Run security threat review, secret-canary tests, dependency/license/CVE scan, and external review if available. (L)
- [ ] Finalize app icon/screenshots/copy/Support and Privacy URLs. (M)
- [ ] Complete privacy manifest, usage descriptions, export compliance, and App Store privacy answers. (M)
- [ ] Add operational dashboards, alerting, key rotation, backup, incident, and rollback runbooks. (M)
- [ ] Run staging soak with real long-running tasks and server restarts. (L)
- [ ] Run TestFlight internal, then limited external beta with feedback triage. (L)
- [ ] Pin compatible Hermes/adapter versions and publish upgrade procedure. (M)
- [ ] Prepare App Store review notes explaining private Tailscale dependency and demo access strategy. (M)

Exit criteria:

- No open S0/S1 defects.
- P0/P1 acceptance in [Product Specification](PRODUCT_SPEC.md) passes.
- Security and push release gates pass.
- Staging contract and physical-device matrix pass.
- Rollback is tested for app, adapter, relay, and Hermes compatibility.

## 14. Cross-cutting workstreams

### Product/design

- Validate navigation and first-run comprehension with prototype users.
- Maintain complete component/state designs.
- Review destructive actions and notification language.
- Verify asset/font rights.
- Keep P0/P1/P2 scope controlled.

### iOS

- App architecture, SwiftUI, networking, cache, media, Keychain, APNs, accessibility, tests.
- Maintain deterministic mocks and supported-version DTOs.
- Keep compiler warnings and concurrency issues at zero.

### Backend/operations

- Edge Basic Auth/bearer translation.
- Mobile adapter and push relay.
- Azure infrastructure, Tailscale ACL, Key Vault, observability, backup, rotation, staging.
- Hermes pinning and upgrade qualification.

### QA/security

- Test matrices and exploratory sessions.
- Contract, replay, failure, accessibility, physical-device, and security validation.
- Release report and accepted-risk record.

## 15. Dependency graph

```text
Phase 0 discovery
  ├─> Phase 1 foundation
  ├─> Phase 2 connection
  │     └─> Phase 3 stable chat
  └─> Phase 4 mobile adapter
          ├─> Phase 5 sessions/interactions
          ├─> Phase 6 rich media/artifacts
          ├─> Phase 7 automations/controls
          └─> Phase 8 push/APNs

Phases 5–8 converge into Phase 9 hardening/release.
```

Foundation/design can proceed while backend contract work begins. Push relay and richer iOS features can progress in parallel after the adapter's IDs/events are stable.

## 16. Feature dependency matrix

| Feature | Stable `/v1` | Mobile adapter | APNs relay |
| --- | --- | --- | --- |
| Basic text chat/SSE | Required | No | No |
| Structured tools | Responses may suffice | Preferred | No |
| Persistent session browsing | No | Required | No |
| Approval/clarification | No in API-server toolset | Required | For background alerts |
| Stop/redirect/queue/steer | Limited/unknown | Required | No |
| Attachments/artifacts | Contract needed | Likely | No |
| Background tasks | Slash fallback | Preferred | Completion alerts |
| Automations | No | Required | Result alerts |
| Skills/toolsets/models | No | Required | No |
| Push notifications | No | Event source | Required |
| Full admin dashboard | No | Deliberately out of scope | No |

## 17. Risks and mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Hermes internal APIs change rapidly | P1 breakage | Pin release; companion adapter; capability/version contracts; fixture CI |
| API server lacks interactive clarify/TTS | Reduced rich UX | Adapter wraps gateway; capability-gate; do not fake prompts |
| Basic Auth and bearer key conflict | Cannot connect securely | Edge validates Basic and injects bearer; test error provenance |
| Tailscale disconnected | App appears broken | Connection-stage diagnostics, cached mode, clear setup guidance |
| iOS suspends stream | Missed completion | APNs relay + foreground reconciliation; no always-on claims |
| Duplicate turns after disconnect | Cost/destructive work repeated | Acceptance state, idempotency, outcome-unknown reconciliation |
| Push relay becomes privacy hotspot | User-content exposure | Generic metadata only, no Hermes credentials/private connectivity, TTL |
| Management surface is too broad | Remote compromise/destruction | Narrow allowlist/scopes, confirmations, defer raw admin features |
| Remote files/tool output are malicious | Client exploit/tracking | Typed rendering, limits, sanitation, system preview, no active HTML |
| Current iOS 26.2 target limits users | Adoption | Decide target early and test APIs with availability annotations |
| App Review cannot access private server | Review delay | Demo/staging plan, review notes, optional safe demo mode if approved |
| One engineer/backend bottleneck | Schedule | Prioritize stable chat; parallelize adapter/relay; strict phase exits |
| Brand assets/font licensing unclear | Release risk | Original assets/system fonts until rights confirmed |

## 18. Open decisions

Resolve and record before the dependent phase:

1. **Minimum iOS:** keep 26.2 or lower for broader compatibility? Before Phase 1.
2. **Device family:** iPhone-only v1 or retain iPad? Before navigation implementation.
3. **Mobile adapter:** approved, location/runtime, and owner? Before P1 commitment.
4. **Authentication:** exact Azure Basic Auth implementation and error contract? Before Phase 2.
5. **Base URL:** one edge origin for `/v1` and `/mobile/v1`, including any path prefix? Before endpoint builder.
6. **Hermes pin:** release/commit and upgrade cadence? Before fixtures.
7. **Markdown:** native/custom versus external renderer? Before Phase 3 UI.
8. **Session continuity:** Responses `previous_response_id`, adapter session, or full-history Chat Completions? Before final chat persistence.
9. **Attachments:** exact upload/association protocol and limits? Before Phase 6.
10. **Voice:** Apple Speech dictation, recorded server transcription, or both? Before permission copy.
11. **Push runtime:** Azure Functions, Container Apps, or existing service; storage/queue choice? Before Phase 8.
12. **APNs account:** final bundle ID/team/key ownership and production access? Before relay deployment.
13. **Privacy mode:** always obscure app switcher or user setting default-on? Before release UX.
14. **High-risk approval:** require biometrics and for which categories? Before Phase 5.
15. **Distribution:** private/Ad Hoc/TestFlight/App Store? Before entitlement/review planning.

## 19. Backlog discipline

For every ticket include:

- user outcome and product priority;
- protocol/capability dependency;
- normal, empty, loading, offline, unauthorized, incompatible, and failure behavior;
- security/privacy/data retention impact;
- accessibility acceptance;
- test layer and fixtures;
- analytics/logging fields, normally metadata-only;
- documentation/compatibility updates;
- rollout and rollback.

A feature is not done merely because its happy-path view renders.

## 20. First implementation backlog

After Phase 0 decisions, create these first tickets in order:

1. Add test/UI test targets and clean build CI.
2. Introduce app shell/environment/routes and Hermes design tokens.
3. Implement `ServerProfile` and endpoint normalization tests.
4. Implement Keychain credential vault and canary tests.
5. Implement origin-bound Basic Auth client and redirect tests.
6. Implement staged connection test with mock scenarios.
7. Build onboarding and editable Connection settings.
8. Implement bounded SSE parser with byte-boundary/fuzz tests.
9. Implement Chat Completions client/event normalization.
10. Build reliable turn coordinator with uncertain-outcome reconciliation.
11. Build chat timeline/composer/Markdown/code/activity UI.
12. Run first real staging/Tailscale vertical-slice test and update fixtures/specs.

This sequence produces evidence early, before investing in broader surfaces.
