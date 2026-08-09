# Quality Strategy

## 1. Quality goals

- No accidental duplicate or lost user turns caused by client retry behavior.
- No credential/content leakage through storage, logs, diagnostics, or push.
- Correct rendering and state transitions across fragmented streaming input.
- Understandable behavior under tailnet, proxy, server, model, and lifecycle failures.
- Critical workflows usable with VoiceOver and large Dynamic Type.
- Compatibility changes detected before shipping against a new Hermes release.
- Fast cached launch and stable scrolling during long streamed conversations.

## 2. Test layers

```text
Static checks
  -> domain/unit tests
  -> protocol/fixture tests
  -> component/repository tests
  -> local mock-server integration tests
  -> UI tests
  -> staging Hermes contract tests
  -> physical-device/Tailscale/APNs tests
  -> release exploratory/security/accessibility pass
```

Each layer must be deterministic where possible. Live model calls are not part of ordinary CI.

## 3. Test targets and support tools

Add:

- `HermesTests` unit/integration target.
- `HermesUITests` UI test target.
- `HermesTestSupport` folder/module for fixtures, fake clock/UUID, URL protocol, and test builders.
- A tiny local mock server runnable in CI that serves health/models, REST, chunked SSE, and WebSocket scenarios.
- Sanitized fixtures from the exact supported Hermes deployment.
- Optional staging contract suite that can run with CI secrets on a disposable Hermes profile.

The mock server may be implemented with a small Swift executable or Python standard-library/a minimal pinned test dependency. It must have a README, deterministic scenario flags, and no production secrets.

## 4. Unit test inventory

### 4.1 Connection and URL handling

- Empty/whitespace/invalid URL.
- HTTPS normalization and trailing slash.
- Intentional reverse-proxy path prefix preserved.
- Query/fragment rejected where inappropriate.
- Embedded credentials rejected.
- IPv4/IPv6/MagicDNS host and explicit port.
- Internationalized host handling.
- Endpoint builder cannot escape base path/origin.
- Same-origin versus cross-origin redirects.
- URL/password/username edits do not mutate active profile before save.

### 4.2 Authentication

- Correct Basic header encoding, including Unicode username/password according to chosen edge contract.
- Empty username/password policy.
- Challenge-based credentials scoped to protection space.
- No Authorization on foreign host, redirect, artifact URL, or relay.
- `401` edge versus upstream-safe error mapping.
- `403`, lockout/rate-limit, cancellation, and timeout mapping.
- Password replacement/keep/remove state machine.

### 4.3 Keychain wrapper

- Add/read/update/delete/idempotent delete.
- Duplicate item recovery.
- Unexpected data decoding failure.
- OSStatus-to-domain error mapping.
- Accessibility/synchronizable/access group attributes asserted through abstraction.
- Password absent from encoded `ServerProfile` and debug descriptions.

Most tests use a fake; run a small real-Keychain suite on simulator/device.

### 4.4 SSE parser

- LF and CRLF.
- Chunk split at every byte boundary, including multi-byte UTF-8 scalar boundaries.
- Multiple events in one chunk.
- Multiple `data:` lines.
- Empty data and blank event terminator.
- Comments/heartbeats.
- `event`, `id`, `retry`, unknown fields.
- `[DONE]` handling by protocol.
- EOF with/without final blank line.
- Invalid UTF-8 policy.
- Oversized line/event/buffer rejection.
- Cancellation and task cleanup.
- Slow chunks and zero-length chunks.
- JSON split across chunks.

Property/fuzz tests should feed random chunk boundaries and malformed fields with strict memory/time limits.

### 4.5 OpenAI event decoding

- Chat Completions role/content deltas, finish reasons, usage, errors.
- Responses text deltas, output item start/end, function call arguments split across events, function outputs, completion/failure.
- Unknown event/item types ignored safely.
- Duplicate event ID deduplicated where applicable.
- Out-of-order/impossible lifecycle reported without crashing.
- Tool calls with missing/invalid JSON arguments displayed as safe raw summaries, never executed.
- Silence token is ordinary stored transcript data unless the protocol says delivery is suppressed.

### 4.6 Turn coordinator

- Only one foreground stream per conversation.
- Stale generation events discarded.
- Cancel local stream versus stop remote work.
- Accepted-before-drop and unaccepted-before-drop transitions.
- Ambiguous send becomes `reconciling`, never automatic resend.
- Idempotency key stable across safe retry.
- App background/termination persistence.
- Transcript reconciliation resolves completed/running/missing outcome.
- Redirect/queue/steer fallback rules, including image-to-queue.
- Duplicate completion from SSE and APNs.

### 4.7 Domain and rendering models

- DTO-to-domain mapping for all message roles/content parts.
- Stable IDs for streamed updates.
- Tool state transition legality.
- Approval/clarification expiry and idempotency.
- Single/multi/free-form validation.
- Usage/cost/byte/duration/date formatting.
- Session lineage/latest descendant.
- Automation schedule/form normalization and execution-content requirement.
- Redaction formatter catches fixture canaries.

### 4.8 Persistence

- Server namespace isolation.
- Upsert and pagination merge.
- Partial server pages do not erase unrelated cache.
- Remote delete and local clear semantics.
- Draft persistence and deletion.
- Reconciliation after crash markers.
- Migrations from every shipped schema.
- Corrupt cache recovery preserves settings/Keychain.
- Artifact LRU/age/size eviction.

### 4.9 Push

- Payload version/category/ID validation.
- Deep-link routing after setup/unlock.
- Unknown server/deleted session/resolved interaction.
- Event deduplication and badge calculation.
- Token change/update/revocation state machine.
- Notification preference mapping.
- Generic body selection; no content fields.
- Signature canonicalization/verification tests in relay code.
- Timestamp/nonce/event replay rejection.
- APNs response retry classification.

## 5. API fixture and contract tests

### 5.1 Sanitized fixtures

Capture from staging:

- `/health` success/degraded variants.
- `/v1/models` success/unauthorized.
- Chat Completions SSE with plain text, multiple tools, tool failure, model failure, usage.
- Responses SSE with function calls/output and unknown events.
- Session list/detail/messages/search/lineage.
- Cron list and every mutation response.
- Skills/toolsets/models/status capabilities.
- Structured approval and clarification through adapter.
- Version/capability response.

Sanitization must replace credentials, hostnames, user content, paths, and IDs with obvious test values. Add secret-canary scan before committing fixtures.

### 5.2 Compatibility matrix

For each supported Hermes/adapter version:

- decode all read DTOs;
- run harmless chat against an isolated profile with stub/cheap model where feasible;
- validate stream lifecycle and cancellation;
- perform management mutations on disposable test records only;
- assert capabilities match actual behavior;
- compare OpenAPI/schema snapshots for breaking changes;
- fail CI or release promotion on unreviewed mutation contract change.

Unknown fields are allowed. Missing required fields or changed semantics require adapter/version update.

## 6. Mock server scenarios

The local harness should support named scenarios:

```text
healthy
basic-auth-rejected
upstream-unauthorized
slow-health
cold-start-then-ready
chat-text-stream
chat-tool-stream
responses-structured-tools
approval-required
clarification-single
clarification-multi
stream-drop-before-accept
stream-drop-after-accept
stream-resume
server-restart
malformed-sse
oversized-event
rate-limited
provider-failure
artifact-download
websocket-auth-close
websocket-reconnect
```

Scenario requests are recorded in memory for assertions. The harness must redact Authorization and never print request bodies by default.

## 7. UI test journeys

### P0

1. Fresh launch -> setup validation -> failed test -> successful save -> chat.
2. Relaunch with saved credential placeholder and cached session.
3. Edit URL/username while retaining password; test and save.
4. Replace password; wrong password leaves prior active configuration intact.
5. Forget server deletes local state and returns to welcome.
6. Send text -> stream -> complete.
7. Stream disconnect -> uncertain/reconcile -> no duplicate.
8. Stop supported versus local disconnect unsupported.
9. Load/reopen cached and refreshed sessions.
10. Offline/Tailscale-unavailable/unauthorized/TLS/incompatible states.

### P1

- Markdown, long code, tables, links, and copy/select.
- Image/file/voice attachment permission and failure paths.
- Tool activity update/collapse/failure.
- Approval deny/approve/expire/double-tap.
- Single/multi/free-form clarification.
- Session search/rename/delete/resume/lineage.
- Background task and notification deep link.
- Automation CRUD/pause/resume/run/error.
- Model/profile/personality/reasoning/skill/toolset capability gating.
- Artifact preview/download/share.
- Notification settings denied/authorized/revoked.

Use launch arguments to load deterministic fake environments; do not depend on a live server in UI CI.

## 8. Accessibility testing

Automated:

- Accessibility identifier uniqueness for interactive controls.
- Missing labels/traits/value checks in critical screens.
- Accessibility Inspector audits where automatable.
- Screenshot/layout tests at extra-small and accessibility-extra-extra-extra-large.

Manual with VoiceOver:

- Connection setup and secure-field behavior.
- Send/stop and streamed response without focus theft.
- Tool activity summary/expansion.
- Approval/clarification ordering and state announcements.
- Attachment picker/preview/removal.
- Session and automation swipe/context actions alternatives.
- Notification deep-link destination.

Also test:

- Reduce Motion.
- Increase Contrast.
- Differentiate Without Color.
- Bold Text and Button Shapes.
- Voice Control.
- Switch Control for critical flows.
- Hardware keyboard if iPad ships.

P0 critical flows must be fully operable without sight.

## 9. Visual and snapshot testing

Snapshot tests are useful for stable design-system components, not token-by-token streaming animation.

Cover:

- every connection pill state;
- user/assistant/system/tool/error messages;
- Markdown/code/diff/table;
- activity stack;
- approval and clarification;
- composer with keyboard/attachments/recording/busy modes;
- session and automation rows;
- empty/loading/error/offline states;
- compact/regular widths;
- default/high contrast and key Dynamic Type sizes.

Pin fonts/assets in tests and review intentional changes. Do not use snapshots as the sole accessibility or behavior test.

## 10. Performance tests

Measure on oldest supported physical device and representative current device:

- cold launch to cached chat;
- database open/migration;
- 1,000-message transcript initial render and scroll;
- 100 KB streamed response with small deltas;
- 100 tool events updating one activity card;
- session search and pagination;
- large code block selection/copy;
- 20 MB attachment staging/upload/download where allowed;
- memory after repeated open/close/stream cycles;
- battery/network impact of reconnect loops.

Initial budgets:

- cached first meaningful screen: <1.5 s;
- ordinary local UI interaction: main-thread stalls <100 ms;
- stream delta batching: visible within ~100 ms without per-token layout churn;
- steady long-chat memory: establish baseline, then no unbounded growth;
- reconnect: bounded exponential backoff, no wake loop in background.

Use Instruments: Time Profiler, Allocations/Leaks, SwiftUI, Network, Energy Log, and Core Data/SwiftData diagnostics where applicable.

## 11. Network resilience matrix

Test on Wi-Fi, cellular where tailnet policy permits, high latency, packet loss, and transitions:

- launch with Tailscale off then on;
- Tailscale on but ACL denies;
- DNS failure;
- TLS failure;
- edge cold start;
- proxy 502/503/504;
- Basic Auth failure and rate limit;
- upstream bearer misconfiguration;
- server restart during connect/stream/tool/approval;
- Wi-Fi to cellular mid-stream;
- app background/foreground during each turn phase;
- process kill after send before acceptance/after acceptance;
- device lock/unlock and protected-data availability.

Use Network Link Conditioner or a controllable proxy in development; never ship interception certificates/settings.

## 12. Security validation

- Static secret scan of repo/build settings/fixtures.
- Dependency CVE and license checks.
- Inspect `UserDefaults`, SwiftData, files, logs, and crash diagnostics with unique secret canaries.
- Authorization cross-origin redirect test.
- Malicious Markdown links/HTML/remote images.
- Oversized/decompression-bomb/path traversal filenames.
- Malformed notification/deep-link IDs.
- Approval replay/cross-session/cross-server/expired response.
- Pairing token replay and webhook signature attacks.
- Relay/API rate limits.
- App switcher privacy screenshot.
- Backup extraction to verify `ThisDeviceOnly` credentials are absent.

A threat-model review is required whenever adding a management mutation, direct notification action, WebView bridge, analytics SDK, or new credential.

## 13. Real-device matrix

At minimum:

- Oldest supported iPhone/iOS.
- Current small-screen iPhone.
- Current large-screen iPhone.
- Current release and next beta iOS during active development.
- iPad compact/regular orientations if target remains universal.
- Physical device for microphone, camera, files, Keychain protection, Tailscale, lock state, and APNs.

Include low storage, low power mode, thermal pressure, interrupted audio, incoming call, and permission changes in Settings.

## 14. APNs staging tests

Use development entitlement for local signed debug build and production environment for TestFlight. Verify:

- initial registration, token rotation, reinstall;
- relay environment/topic selection;
- foreground/background/terminated delivery;
- Focus/summary/quiet hours;
- deep link with Tailscale on/off;
- duplicate/collapsed/out-of-order events;
- APNs 410/429/5xx handling;
- relay outage and outbox recovery;
- generic lock-screen preview;
- revoked/forgotten pairing receives no further notifications.

Simulator push injection can test payload routing but does not replace provider-to-device APNs tests.

## 15. CI pipeline

Recommended gates:

1. Markdown link/lint and secret scan.
2. Swift format/lint if adopted, configured to minimize style-only churn.
3. Build app for simulator without signing.
4. Unit tests with code coverage.
5. Mock-server integration tests.
6. UI smoke tests on one simulator; expanded matrix nightly.
7. Relay/backend tests and dependency scan.
8. Sanitized fixture/canary scan.
9. Optional staging Hermes contract tests on protected/nightly workflow.
10. Archive validation on release branch.

Do not expose credentials to pull requests from forks. Staging tests use least-privilege disposable profiles.

## 16. Defect severity

- **S0 Critical:** credential exposure, unauthorized remote action, data destruction, public API exposure.
- **S1 High:** duplicate destructive turn, wrong-session approval, chat unusable, persistent crash/data corruption, push cross-user delivery.
- **S2 Medium:** recoverable feature failure, incorrect non-destructive state, serious accessibility blocker outside critical path.
- **S3 Low:** visual polish, minor copy/layout issue, noncritical diagnostic gap.

Release blocks on any open S0/S1, P0 accessibility blocker, or unexplained contract test failure.

## 17. Release test report

Each candidate records:

- app build/commit and Hermes/adapter versions;
- Xcode/iOS/device matrix;
- automated results and known flaky tests;
- staging contract result;
- security/canary scan result;
- accessibility checklist;
- APNs end-to-end result;
- performance comparison to baseline;
- open defects and accepted risks;
- rollback version and server compatibility.

## 18. Definition of done for a feature

- Product and error-state acceptance criteria implemented.
- Capability and permission behavior defined.
- Unit/integration/UI coverage at appropriate layers.
- Accessibility labels, focus, Dynamic Type, contrast, and Reduce Motion checked.
- Security/privacy logging and data retention reviewed.
- Offline/background/reconnect behavior tested.
- Documentation and compatibility matrix updated.
- No new compiler warnings or relevant static-analysis findings.
- Tested against mock and, where needed, pinned staging Hermes.
