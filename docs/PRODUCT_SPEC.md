# Product Specification

## 1. Document control

- **Product:** Hermes for iPhone
- **Status:** Development specification
- **Baseline date:** August 6, 2026
- **Audience:** Product, design, iOS, backend, QA, and operations
- **Related:** [Architecture](TECHNICAL_ARCHITECTURE.md), [integration](HERMES_INTEGRATION.md), [design](DESIGN_SYSTEM.md), [delivery](DELIVERY_PLAN.md)

## 2. Product summary

Hermes for iPhone is a private, native mobile client for a user-owned Hermes Agent deployed on Azure and reachable through Tailscale. It prioritizes conversational access while exposing the Hermes capabilities that matter away from a desktop: streamed agent work, resumable sessions, approvals and clarification, attachments and artifacts, background tasks, automations, skills, memory visibility, model controls, status, and push notifications.

The app is a client, not an agent runtime. Tools execute on the remote Azure host. The app must make that boundary explicit whenever files, terminal commands, browser work, or local-sounding operations are shown.

## 3. Problem statement

Hermes already works through CLI, desktop, web, and messaging gateways, but an iPhone user needs a dedicated interface that:

- preserves the rich structure of agent events instead of flattening everything into text;
- securely reaches a private remote instance without publishing its agent API;
- handles long-running work and iOS suspension through notifications;
- makes approvals and clarifying questions fast and safe;
- keeps sessions, artifacts, skills, and automations understandable on a small screen;
- follows Hermes' official design language rather than looking like a generic chat wrapper.

## 4. Goals

1. Connect to one user-configured Hermes endpoint using editable URL, username, and password.
2. Deliver a polished chat loop with resilient streaming, cancellation, redirection, retry, and recovery.
3. Preserve structured reasoning visibility, tool activity, approvals, questions, attachments, and artifacts where the server exposes them.
4. Support persistent session browsing, search, resume, rename, delete, usage, and lineage.
5. Make background work and scheduled automations useful on mobile with reliable APNs delivery.
6. Expose safe, capability-gated management for models, profiles, skills, toolsets, memory status, and health.
7. Meet iOS accessibility, privacy, security, and lifecycle expectations.

## 5. Non-goals

- Running the Hermes agent, terminal, models, or tool sandbox on the iPhone.
- Replacing the full desktop administration dashboard in the first release.
- Maintaining an always-on socket while iOS has suspended the app.
- Exposing the Hermes API or Azure VM publicly for chat.
- Editing provider API keys, arbitrary environment variables, raw YAML, hooks, MCP servers, plugins, or gateway platform credentials in v1.
- Silent auto-approval of dangerous commands.
- Claiming compatibility with untested Hermes versions.
- Mirroring all remote files offline.

## 6. Primary persona

**Owner/operator:** a technically capable individual who operates a personal Hermes instance on Azure, has Tailscale on the iPhone, and wants to interact with and supervise the agent throughout the day.

Key needs:

- ask for work immediately;
- understand whether Hermes is connected, thinking, using tools, waiting, or complete;
- correct or stop work mid-turn;
- answer approvals and multi-select clarification prompts;
- reopen prior context;
- inspect and share outputs;
- launch unattended tasks and be notified when they finish;
- diagnose connectivity without exposing credentials.

## 7. Product principles

- **Conversation first:** opening the app should reach the current chat in one action.
- **Show work without noise:** group tool activity into collapsible, live-updating cards.
- **Remote is explicit:** label the active server/profile and remote execution context.
- **Safe by default:** confirmations, redaction, generic notification previews, and no insecure transport.
- **Graceful capability negotiation:** unsupported features disappear or explain their prerequisite.
- **Fast recovery:** drafts, pending sends, stream reconnection, and session refresh survive ordinary interruptions.
- **Hermes, not generic AI:** preserve Hermes terminology, teal/cream palette, technical typography, and agent-state character.

## 8. Information architecture

### iPhone

A four-tab shell:

1. **Chat** — active conversation, session switcher, composer, task activity.
2. **Sessions** — recent/searchable history, background sessions, details, and usage.
3. **Automations** — cron jobs, next run, history/status, pause/resume/run-now, create/edit.
4. **Settings** — connection, agent profile/model, skills/tools, notifications, appearance, diagnostics.

Global destinations presented as sheets or pushes:

- Server setup and connection diagnostics
- Artifact/file preview
- Approval and clarification
- Model/profile picker
- Skills browser
- Agent status

### iPad, if retained

Use `NavigationSplitView`: session/sidebar navigation, conversation content, optional inspector. iPad support must not delay iPhone v1.

## 9. Core user journeys

### 9.1 First connection

1. Launch into welcome/setup.
2. Enter display name (optional), server URL, username, and password.
3. App normalizes the URL and explains Tailscale must be connected.
4. Tap **Test connection**.
5. App checks DNS/TLS/HTTP authentication, `/health`, `/v1/models`, streaming support, server version, and optional management capabilities.
6. Show actionable results without logging secrets.
7. Save only after successful authentication, or allow an explicit save-offline action.
8. Request notification permission only after explaining its value, not on first frame.
9. Open a new or most-recent chat.

### 9.2 Send and supervise a request

1. Type, dictate, paste, or attach content.
2. Send immediately; retain an exact local draft until accepted.
3. Show queued/sending state, then streamed assistant text and grouped activity.
4. Present tool name, safe summary, status, duration, and expandable redacted details.
5. Let the user stop, redirect, queue, or steer depending on server capability.
6. Surface a completion state, usage summary, and generated artifacts.
7. Persist cache and reconcile with the server transcript.

### 9.3 Approval or clarification

1. Agent emits a structured approval or question event.
2. App raises a prominent inline card; optional notification if backgrounded.
3. Approval shows command/action, remote working directory, risk classification, and scope.
4. User approves once, denies, or answers single/multi-select/free-form clarification.
5. Response is idempotent; duplicate taps cannot submit twice.
6. Expired prompts explain that the turn must be retried.

### 9.4 Resume prior work

1. Browse or search sessions.
2. See title, source, model, last activity, message/tool counts, and preview.
3. Open server-authoritative transcript.
4. Follow latest descendant when compression/resume created lineage.
5. Resume, rename, share/export, or delete with confirmation.

### 9.5 Run unattended work

1. Use `/background` or a first-class background-task affordance.
2. App confirms isolated context and delivery behavior.
3. User leaves or iOS suspends the app.
4. Relay sends completion/failure/approval-required notification.
5. Tap deep-links to the relevant session/task and refreshes from Hermes.

### 9.6 Manage an automation

1. View enabled/paused jobs ordered by next run.
2. Inspect prompt/script, schedule, profile, model, skills, toolsets, delivery, and recent status.
3. Create from natural-language-friendly fields or an upstream blueprint.
4. Validate schedule and execution content.
5. Save, pause/resume, run now, or delete with confirmation.

### 9.7 Edit connection

1. Open Settings > Connection.
2. Edit URL, username, or password; password is never prefilled as readable text.
3. Test proposed settings without replacing the working profile.
4. On save, cancel streams, invalidate capability cache, switch cache namespace, and reconnect.
5. Provide **Forget server** to delete credentials, cached data, push pairing, and pending drafts after confirmation.

## 10. Feature specification and priority

Priority meanings: **P0** first usable release, **P1** first full release, **P2** later enhancement.

### 10.1 Connection and onboarding

| Feature | Priority | Requirements |
| --- | --- | --- |
| Editable server URL | P0 | HTTPS URL; normalize trailing `/`; accept optional path prefix; reject embedded credentials |
| Username/password | P0 | Basic Auth at Azure edge; username non-secret, password Keychain-only; editable and removable |
| Test connection | P0 | Stage-by-stage diagnosis; timeout/cancel; no secret echoes |
| Tailscale awareness | P0 | Explain unreachable tailnet host; deep-link to Tailscale settings/app when feasible; never attempt VPN control |
| Multiple server profiles | P2 | Architecture supports IDs/namespaces; v1 UI has one active profile |
| Capability discovery | P0 | Persist by server/version with TTL; manual refresh; feature gating |
| Offline launch | P0 | Open cached sessions/read-only settings; clear offline banner |

### 10.2 Chat and composer

| Feature | Priority | Requirements |
| --- | --- | --- |
| Text chat | P0 | Multiline composer, send, draft preservation, retry, copy, selection |
| Streaming text | P0 | SSE incremental rendering, throttled UI updates, reconnect/reconcile |
| Markdown | P0 | Headings, lists, links, quotes, tables, inline/fenced code; safe link handling |
| Code blocks | P0 | Syntax-neutral monospace initially; copy; horizontal scroll; language label |
| Tool activity | P0 | Structured Responses events when available; grouped fallback progress otherwise |
| Stop generation | P0 | Cancel server turn if supported; otherwise cancel local stream and explain limitation |
| Retry/undo/new/title | P1 | First-class UI mapped to structured RPC or slash-command fallback |
| Busy input modes | P1 | Redirect, queue, steer; show selected semantics and fallback |
| Reasoning visibility | P1 | Off/show and effort controls only when supported; never fabricate hidden reasoning |
| Slash commands | P1 | Autocomplete supported commands and skills; raw text remains available |
| Draft stash/history | P2 | Multiple local drafts per server/session, encrypted or protected storage |
| Reactions | P2 | Render/send when the chosen protocol exposes stable message IDs and reactions |

### 10.3 Rich input and output

| Feature | Priority | Requirements |
| --- | --- | --- |
| Photo/document attachment | P1 | Picker, preview, size/type validation, upload progress, cancellation |
| Camera capture | P1 | Permission just-in-time; image compression without destroying legibility |
| Voice dictation | P1 | Prefer system Speech framework for composer dictation; clear privacy disclosure |
| Voice messages | P1 | Record via AVFoundation, waveform/duration, upload, server transcription path |
| Spoken replies | P2 | Play server audio artifact or app-local speech only when clearly labeled |
| File/artifact preview | P1 | Image, PDF, text, audio, video/system Quick Look; safe download/share |
| File browser | P2 | Sandboxed roots only; list/read/download first; write/delete later with confirmation |
| Generated image gallery | P1 | Inline thumbnail, full screen, save/share, provenance metadata if available |

### 10.4 Interactive agent controls

| Feature | Priority | Requirements |
| --- | --- | --- |
| Dangerous-command approval | P0 | Structured prompt preferred; command, cwd, impact, expiry; approve/deny only |
| Clarification | P0 | Single select, multi-select, free-form; accessible controls; idempotent submission |
| Background task launch | P1 | Isolated-context warning, task/session identity, status, notification linkage |
| Delegation visualization | P2 | Parent/child sessions, status, results; no arbitrary terminal control |
| Filesystem rollback | P2 | List checkpoints and restore only after explicit typed/biometric confirmation |

If the API-server surface cannot emit interactive prompts, the corresponding feature is disabled until a supported gateway JSON-RPC or companion adapter is deployed. The app must not parse arbitrary assistant prose into approvals.

### 10.5 Sessions and history

| Feature | Priority | Requirements |
| --- | --- | --- |
| Recent sessions | P0 | Pagination, pull-to-refresh, source filter, cached loading |
| Transcript | P0 | User/assistant/system/tool messages; timestamps; attachment metadata |
| Search | P1 | Server FTS; debounce; highlighted snippets; source filters |
| Rename/delete | P1 | Optimistic rename with rollback; destructive confirmation |
| Resume/lineage | P1 | Follow latest descendant and explain compression lineage |
| Usage | P1 | Input/output/cache/reasoning tokens, cost where server reports it |
| Export/share | P2 | Server export or local Markdown/PDF; redact system/tool secrets by default |

### 10.6 Automations

| Feature | Priority | Requirements |
| --- | --- | --- |
| Job list/detail | P1 | Enabled state, schedule, next/last run, result/error, delivery target |
| Pause/resume/run now | P1 | Idempotent actions and current state refresh |
| Create/edit/delete | P1 | Name, prompt/script, schedule, skills, model/provider, workdir, toolsets, delivery |
| Blueprints | P2 | Browse and instantiate parameterized upstream blueprints |
| Run history | P2 | Requires a stable upstream history endpoint or session linkage |

### 10.7 Skills, memory, tools, model, and profile

| Feature | Priority | Requirements |
| --- | --- | --- |
| Active model/profile summary | P0 | Always visible from chat header or status sheet |
| Model picker | P1 | Configured models only by default; capability and cost warning; confirmation for expensive choices |
| Personality/reasoning | P1 | Session-scoped controls; clear global-vs-session labeling |
| Skills list/detail | P1 | Enabled state, category, description, Markdown content |
| Enable/disable skill | P1 | Confirmation if active work may be affected |
| Skills Hub install | P2 | Preview trust, scan verdict, findings, and policy before install |
| Toolsets | P1 | List and enable/disable; explain tools run remotely |
| Memory status | P1 | Provider/status and non-destructive summary only |
| Memory editing/reset | P2 | Reset requires biometric/typed confirmation; raw memory editing needs separate design review |
| Profile switching | P2 | Capability-gated; cache namespace and active stream handling |

### 10.8 Status and diagnostics

| Feature | Priority | Requirements |
| --- | --- | --- |
| Connection state | P0 | Offline, connecting, authenticated, degraded, unauthorized, incompatible |
| Agent/gateway status | P1 | Version, gateway state, active sessions, platform health |
| System health | P2 | CPU/memory/disk/uptime with privacy-safe presentation |
| Diagnostics export | P1 | Locally generated, redacted report; user previews before sharing |
| Update/doctor/restart | P2 | High-impact admin controls behind confirmation and capability/role checks |

### 10.9 Notifications

| Feature | Priority | Requirements |
| --- | --- | --- |
| Completion/failure | P1 | Background and cron outcomes; generic preview by default |
| Approval/question required | P1 | Time-sensitive where justified; deep-link to prompt |
| Long-running status | P2 | Opt-in and rate-limited |
| Per-category preferences | P1 | Completion, failure, approval, automation, quiet hours, preview content |
| Badge count | P1 | Unread actionable/completed events, server reconciled where possible |

See [Push Notifications](PUSH_NOTIFICATIONS.md).

## 11. Chat state model

A turn can be:

- `draft`
- `queued`
- `sending`
- `thinking`
- `streaming`
- `waitingForApproval`
- `waitingForClarification`
- `runningTools`
- `stopping`
- `completed`
- `failed`
- `interrupted`
- `reconciling`

The UI may display combined phases but the internal model must preserve them. One session may have one foreground turn and multiple background/delegated tasks.

## 12. Empty, loading, and error states

Every feature requires designed states for:

- no server configured;
- Tailscale disconnected or hostname not resolvable;
- server asleep/cold-starting;
- wrong username/password;
- TLS or proxy failure;
- Hermes API unauthorized/misconfigured;
- incompatible or missing endpoint;
- no sessions/jobs/skills;
- initial load, paginated load, refresh, and stale cache;
- stream dropped before or after server accepted the request;
- server restarted or version changed;
- expired approval/question;
- attachment too large/unsupported;
- rate limit/model/provider/tool failure.

Errors must answer: what happened, whether work may still be running, and what the user can do next.

## 13. Accessibility requirements

- Support Dynamic Type through accessibility sizes without clipping composer or controls.
- Minimum 44×44 point interactive targets.
- VoiceOver labels announce role, sender, state, code language, tool status, and attachment type.
- Stream updates must not continuously steal VoiceOver focus; announce meaningful phase changes only.
- Never communicate status by color alone.
- Respect Reduce Motion, Reduce Transparency, Increase Contrast, Button Shapes, and Bold Text.
- Full keyboard navigation for iPad/hardware keyboards if iPad ships.
- WCAG AA contrast target for text and controls; upstream rule floors: body text at least 12 px equivalent and no text opacity below 0.7.

## 14. Privacy behavior

- Notification previews default to “Hermes completed a task” rather than response content.
- App switcher snapshot obscures conversation and credentials when privacy mode is enabled; credential screens are always obscured.
- Clipboard copy is explicit; sensitive command/tool payloads are not copied automatically.
- Analytics, if introduced, are opt-in and contain no prompts, responses, paths, filenames, URLs, usernames, or stable server identifiers.
- Local caches are protected with complete-file protection and can be cleared per server.

## 15. Product analytics and success measures

No third-party analytics are required for v1. If privacy-safe local metrics are later added, evaluate:

- connection setup completion and failure stage;
- successful message send rate;
- median time to first streamed content;
- stream recovery rate;
- crash-free sessions;
- notification delivery-to-open rate without content logging;
- approval response latency;
- accessibility audit completion;
- percentage of surfaced features disabled by capability mismatch.

Targets for release candidate:

- ≥99% app-side successful processing of valid mocked streams.
- No credential or message content in logs and diagnostics fixtures.
- Connection recovery without duplicate user turns in tested disconnect windows.
- Cold launch to cached conversation under 1.5 seconds on the oldest supported device target.
- 100% P0 critical flows operable with VoiceOver.

## 16. P0 release acceptance

The P0 internal build is accepted when:

1. A user can add, test, edit, and forget the URL/username/password profile.
2. Credentials survive relaunch in Keychain and never appear in local preferences/logs.
3. The app works only through a reachable, authenticated HTTPS endpoint.
4. User can create a chat request and render SSE response safely.
5. Drafts and uncertain-send states prevent accidental duplicate work.
6. Recent sessions and transcripts load from server/cache.
7. Markdown/code, tool progress fallback, stop/cancel semantics, and actionable errors work.
8. Capability discovery disables unsupported P0-adjacent features honestly.
9. Unit/integration/UI tests cover setup, auth, stream parsing, reconnect, and logout.
10. Security review finds no critical/high issues.

## 17. Full v1 acceptance

In addition to P0:

- Structured tool events and interactive approvals/questions work against the pinned server adapter.
- Attachments and artifact previews work for supported types.
- Session search/rename/delete/resume and usage work.
- Automations support list/detail/create/edit/pause/resume/run/delete.
- Model, personality/reasoning, skills, and toolsets are manageable within defined safety limits.
- APNs supports completion, failure, approval, and clarification deep links.
- Voice dictation/message flow meets permission and interruption requirements.
- Accessibility, localization readiness, performance, and device-matrix testing pass.

## 18. Deferred ideas

- Siri/App Intents for “Ask Hermes” and “Start background task.”
- Widgets and Live Activities for long-running tasks, subject to server event support and ActivityKit policy.
- Multiple Hermes instances and fast profile switching.
- Apple Watch approval companion after security review.
- End-to-end encrypted rich notification content.
- Offline message queue with explicit expiry and user confirmation.
- Full admin console, MCP/plugin management, raw config editor, and terminal emulator.
