# Hermes Integration Specification

## 1. Scope and research baseline

This document records the integration surface observed in official Nous Research sources on August 6, 2026. The deployed instance must be pinned and tested; upstream `main` changes frequently.

Primary sources:

- [Hermes Agent repository](https://github.com/NousResearch/hermes-agent)
- [Open WebUI/API server guide](https://hermes-agent.nousresearch.com/docs/user-guide/messaging/open-webui)
- [Messaging gateway guide](https://hermes-agent.nousresearch.com/docs/user-guide/messaging)
- [CLI guide](https://hermes-agent.nousresearch.com/docs/user-guide/cli)
- Upstream dashboard client: `web/src/lib/api.ts` and `web/src/lib/gatewayClient.ts`

The integration is split into three surfaces with different stability and authentication:

1. **API server** — OpenAI-compatible, intended for external clients; stable base for chat.
2. **Dashboard management API** — broad `/api/*` control surface intended for the Hermes web dashboard; internal and version-sensitive.
3. **TUI gateway JSON-RPC** — rich session/event protocol over `/api/ws`; internal and version-sensitive.

## 2. Required Azure/Hermes deployment

### 2.1 Hermes API server

Official setup uses:

```bash
hermes config set API_SERVER_ENABLED true
hermes config set API_SERVER_KEY '<random-secret>'
```

Relevant upstream defaults:

| Setting | Default | Required deployment behavior |
| --- | --- | --- |
| `API_SERVER_ENABLED` | `false` | Enable |
| `API_SERVER_HOST` | `127.0.0.1` | Keep loopback when edge proxy is on same host/container network |
| `API_SERVER_PORT` | `8642` | Keep or explicitly configure proxy upstream |
| `API_SERVER_KEY` | required | Long random value stored only server-side |
| `API_SERVER_MODEL_NAME` | profile/default | Optional user-friendly model identity |

The API server is an agent runtime. Terminal, file, browser, MCP, and other tools run on the Azure host, not the iPhone.

### 2.2 Tailscale reachability

As deployed (see `hermes-agent-azure`):

- The Azure Container App runs a Tailscale userspace sidecar that advertises the `svc:hermes` Service.
- iPhone has the Tailscale app installed and connected to the same tailnet.
- The Service hostname resolves through MagicDNS, e.g. `hermes.example-tailnet.ts.net`.
- `tailscale serve` publishes the dashboard on `443` and the API server on `8443`.
- Hermes' API server binds to `127.0.0.1:8642` and is never published on the public Azure ingress.
- The tailnet policy must grant the user `tcp:443` **and** `tcp:8443` on `svc:hermes`, and the Service must declare both endpoints. Missing `tcp:8443` fails closed at the tailnet, not at Hermes.
- HTTPS terminates at the Tailscale front end with a trusted certificate. Do not disable ATS or certificate validation.

Tailscale connectivity is necessary but not a replacement for application-layer authentication.

### 2.3 Authentication contract

The app always allows the user to set and edit:

- Server URL, e.g. `https://hermes.example-tailnet.ts.net:8443`
- Username
- Password / API key

The deployed flow has no header-rewriting edge. `tailscale serve` is a pass-through reverse proxy:

```text
Client Authorization: Bearer <API_SERVER_KEY>
        |
        v
Tailscale Service :8443 (pass-through reverse proxy)
        |
        v
Hermes API server on 127.0.0.1:8642
```

Requirements for this deployment:

- Leave the username blank so the app sends the secret as a Bearer key.
- Use a long random `API_SERVER_KEY`; it is a full-access agent runtime credential.
- Store it only in the Keychain, never in preferences, logs, or source.
- Rotate it in Key Vault and in the app together; there is no per-user revocation.
- Restrict who can reach `tcp:8443` with Tailscale grants, since the tailnet is the only layer that distinguishes users.
- Preserve streaming (`text/event-stream`) without proxy buffering.

The dashboard on `443` keeps its own Basic username/password and is a browser surface only.

#### Alternative: Basic-to-Bearer edge

If a translating edge is introduced later, it must:

```text
Client Authorization: Basic <username:password>
        |
        v
Edge authenticates and authorizes user
        |
        | remove Basic header
        | add Authorization: Bearer <API_SERVER_KEY>
        v
Hermes API server
```

- Use Argon2id/bcrypt/scrypt-equivalent password verification or a managed identity provider at the edge; never plaintext password storage.
- Rate-limit failed authentication by identity/source without permanently locking out the owner.
- Return `401` plus an appropriate Basic challenge for invalid credentials.
- Return `403` for authenticated users lacking permission.
- Never forward Basic credentials to Hermes or include them in proxy logs.
- Never send the API server key to the phone.
- Preserve streaming, long upstream/read timeouts with heartbeats, and request cancellation.
- Restrict allowed methods and paths by client role.

The app supports both contracts through the same fields via `AuthenticationStrategy`. Do not silently reinterpret the password as the Hermes bearer key unless that deployment contract is explicitly chosen and documented.

## 3. Stable API-server surface

### 3.1 Health

```http
GET /health
```

Expected use: service reachability and basic status. Official examples show no bearer header required upstream, but the Azure edge may require Basic Auth uniformly.

The client should treat the payload as extensible and require only a successful status plus an optional `status: "ok"`.

### 3.2 Models

```http
GET /v1/models
Authorization: Bearer <API_SERVER_KEY>   # injected by edge
```

OpenAI-compatible list. Hermes commonly advertises one model representing the configured profile/agent. The app uses it to prove authenticated upstream access and to identify the chat model; model administration uses the optional management surface.

### 3.3 Chat Completions

```http
POST /v1/chat/completions
Content-Type: application/json
Accept: text/event-stream

{
  "model": "hermes-agent",
  "messages": [
    {"role": "user", "content": "Hello"}
  ],
  "stream": true
}
```

Properties from official docs:

- OpenAI-compatible request/response shape.
- Full conversation history is normally client-supplied.
- Hermes creates an `AIAgent` and runs its configured tools on the server.
- Streaming includes text and may include inline tool progress text.
- Final result is returned through SSE chunks.

Use as the universal fallback. Inline tool-progress prose is presentation-only. It must not be parsed into trusted command approvals, file operations, or structured tool metadata.

### 3.4 Responses API

```http
POST /v1/responses
Content-Type: application/json
Accept: text/event-stream

{
  "model": "hermes-agent",
  "input": [{"role": "user", "content": "Hello"}],
  "stream": true,
  "previous_response_id": "optional-server-response-id"
}
```

Official docs describe this as experimental but useful for:

- server-side continuation through `previous_response_id`;
- spec-native text delta events;
- `function_call` and `function_call_output` items;
- richer structured tool UI.

Preferred when the pinned Hermes version passes contract tests. Unknown Responses events are ignored safely and retained only as redacted type names in diagnostics.

### 3.5 API-server limitations

The official `hermes-api-server` toolset drops `clarify` and `text_to_speech` because it is considered a programmatic surface without an interactive user. Therefore stable OpenAI-compatible API access alone may not support:

- interactive dangerous-command approvals;
- native clarification prompts;
- all session management actions;
- direct voice reply streaming;
- reactions/typing/message identities;
- cron/skills/toolset administration.

These need a tested rich adapter or upstream extension. Product UI must reflect the actual capability set.

## 4. Dashboard management API

### 4.1 Stability warning

The web dashboard is a machine-level management surface. Its API is broad, privileged, and not documented as a stable external API. It uses dashboard-specific authentication:

- loopback mode: ephemeral `X-Hermes-Session-Token` injected into served HTML;
- gated mode: OAuth/session cookie;
- WebSockets: a single-use ticket with approximately 30-second TTL;
- some endpoints support profile query/body scoping.

The iOS app must not scrape tokens from dashboard HTML or depend on loopback injection. Management support requires one of:

1. a supported native OAuth/PKCE flow advertised by the pinned dashboard;
2. an Azure companion adapter exposing a narrow, versioned mobile API;
3. a deliberately configured reverse-proxy contract that authenticates the user and provides a supported server-side dashboard credential.

Recommendation: build a narrow companion adapter for P1 management and interactive events. Keep `/v1` chat directly compatible.

### 4.2 Observed endpoint inventory

Read-only/safe candidates for an adapter:

| Capability | Upstream endpoints |
| --- | --- |
| Status | `GET /api/status` |
| Sessions | `GET /api/sessions`, `/api/sessions/search`, `/api/sessions/{id}`, `/messages`, `/latest-descendant`, `/stats` |
| Usage | `GET /api/analytics/usage`, `/api/analytics/models` |
| Model | `GET /api/model/info`, `/api/model/options`, `/api/model/auxiliary` |
| Skills | `GET /api/skills`, `/api/skills/content` |
| Toolsets | `GET /api/tools/toolsets`, `/{name}/config` |
| Cron | `GET /api/cron/jobs`, `/api/cron/delivery-targets`, `/api/cron/blueprints` |
| Files | `GET /api/files`, `/api/files/read` |
| Memory | `GET /api/memory`, `/api/memory/providers/{name}/config` |
| Profiles | `GET /api/profiles`, `/api/profiles/active` |
| Platforms | `GET /api/messaging/platforms` |
| System | `GET /api/system/stats` |

Mutation candidates, gated by version and confirmations:

| Capability | Upstream endpoints |
| --- | --- |
| Sessions | `PATCH/DELETE /api/sessions/{id}`, bulk/empty/prune/import operations |
| Model | `POST /api/model/set` |
| Skills | create/update/toggle and Hub install/uninstall/update endpoints |
| Toolsets | enable/provider/env/post-setup endpoints |
| Cron | create/update/delete/pause/resume/trigger and blueprint instantiate endpoints |
| Files | multipart upload, mkdir, delete |
| Profile | set active, create/update/rename/delete, soul/model endpoints |
| Operations | gateway start/stop/restart, update, doctor, security audit, backup/import |
| Memory | provider setup/select and reset |

Do not expose raw config/env, provider credentials, credential pools, hooks, MCP, plugins, backups/imports, pairing administration, or Hermes update/restart in v1 unless separately threat-modeled.

### 4.3 Narrow companion adapter

Recommended mobile adapter prefix: `/mobile/v1`.

Responsibilities:

- authenticate Azure edge identity;
- translate to local Hermes interfaces without revealing dashboard tokens;
- expose a small OpenAPI-described allowlist;
- normalize upstream DTO changes;
- emit capabilities and Hermes version;
- enforce read/write/admin scopes;
- issue stable interaction/session IDs;
- sign push events;
- redact secrets and constrain file roots;
- attach idempotency keys to mutating operations.

Minimum candidate endpoints:

```text
GET    /mobile/v1/capabilities
GET    /mobile/v1/status
GET    /mobile/v1/sessions
GET    /mobile/v1/sessions/{id}
GET    /mobile/v1/sessions/{id}/messages
PATCH  /mobile/v1/sessions/{id}
DELETE /mobile/v1/sessions/{id}
GET    /mobile/v1/sessions/search
GET    /mobile/v1/automations
POST   /mobile/v1/automations
PATCH  /mobile/v1/automations/{id}
POST   /mobile/v1/automations/{id}/pause|resume|trigger
DELETE /mobile/v1/automations/{id}
GET    /mobile/v1/skills
PATCH  /mobile/v1/skills/{name}
GET    /mobile/v1/toolsets
PATCH  /mobile/v1/toolsets/{name}
GET    /mobile/v1/models
PATCH  /mobile/v1/session/{id}/settings
POST   /mobile/v1/push/pair
DELETE /mobile/v1/push/pair/{id}
WS/SSE /mobile/v1/events
```

The exact adapter language/runtime should align with the Azure deployment. Python/FastAPI colocated with Hermes minimizes DTO translation cost; a sidecar process limits coupling.

## 5. JSON-RPC/WebSocket surface

The dashboard source connects to:

```text
wss://<dashboard-host>/<optional-prefix>/api/ws?<ticket-or-token>
```

It uses a newline-delimited JSON-RPC dialect shared with the TUI gateway. Upstream examples explicitly mention:

- request `session.create` returning `session_id`;
- request `prompt.submit` with `session_id` and text;
- event `message.delta` with text payload.

Do not infer the full method/event schema. During implementation:

1. Pin the Hermes commit/release.
2. Extract dispatcher method registry and event DTOs from `tui_gateway` and shared TypeScript package.
3. Save sanitized protocol fixtures in tests.
4. Generate/hand-code strict Codable DTOs.
5. Negotiate capability/version before sending.
6. Treat unknown methods/events as unsupported, not fatal where safe.

Reconnect guidance from upstream dashboard behavior:

- exponential delay 1, 2, 4, 8… seconds capped at 30 seconds;
- normal close `1000` is terminal;
- auth closes `4401`/`4403` are terminal until reauthentication;
- network/restart closes are retryable with a bounded attempt count;
- every gated-mode reconnect requires a fresh one-time ticket.

The companion adapter should use a mobile-specific short-lived WebSocket ticket obtained through authenticated REST, avoiding long-lived credentials in the URL.

## 6. Session behavior

Hermes persists sessions in SQLite with metadata, messages, tool calls, lineage, timestamps, tokens, and FTS search.

Relevant observed fields:

```text
id, source, model, title, started_at, ended_at, last_active,
is_active, message_count, tool_call_count, input_tokens,
output_tokens, preview, parent_session_id
```

Message roles: `user`, `assistant`, `system`, and `tool`, with content, tool calls, tool name/call ID, and timestamp.

Rules for the app:

- Remote session ID is opaque.
- Source filters should initially include API/mobile/CLI/gateway sessions only when the user opts in.
- When resuming, call latest-descendant so compressed/resumed lineage is current.
- Preserve server timestamps and render in local timezone.
- Session `/model` overrides may persist through gateway restarts and reset on `/new`; do not label them global.
- `/new` or reset creates a new conversation context, not just a local blank screen.

## 7. Commands and feature mapping

When structured methods exist, use them. Slash commands are fallback/user-visible escape hatches.

| App action | Hermes command/behavior |
| --- | --- |
| New conversation | `/new` or `/reset` |
| Select model | `/model [provider:model]` |
| Personality | `/personality [name]` |
| Retry/undo | `/retry`, `/undo` |
| Stop | `/stop` |
| Compress | `/compress` |
| Rename | `/title [name]` |
| Resume/list/search | `/resume`, `/sessions [all] [search query]` |
| Usage | `/usage`, `/insights [days]` |
| Reasoning | `/reasoning [level|show|hide]` |
| Background task | `/background <prompt>` |
| Rollback | `/rollback [number]` |
| Skill invocation | `/<skill-name>` |
| Approval | `/approve` or structured response |
| Denial | `/deny` or structured response |

The app must not send a slash command invisibly when command semantics might differ by version without showing the action to the user.

## 8. Busy input and cancellation

Hermes supports:

- **interrupt** — redirect active generation while retaining visible reasoning/completed work; running tools finish at a safe boundary;
- **queue** — send as next turn;
- **steer** — inject after the next tool result; falls back to queue before start or with images;
- **stop** — hard stop foreground work.

The app exposes only modes advertised by the adapter. Cancelling the iOS HTTP request is not equivalent to stopping the remote agent. The UI must distinguish **Stop remote work** from **Disconnect stream**.

## 9. Tools, interactions, and safety

Hermes can run terminal/file/web/browser/code/image/TTS/MCP tools. Mobile rendering requirements:

- use stable tool IDs;
- display tool name and a redacted summary;
- show remote cwd/host context for terminal/file operations;
- cap output size and load full output on demand;
- never render tool HTML as executable content;
- prevent automatic URL opens;
- preserve failure/cancel state.

Approval and clarification must be structured. Hermes clarification supports single-select, multi-select, and free-form answers. An interaction includes:

```text
interaction_id
session_id
kind
prompt/title
choices[]
allow_multiple
allow_freeform
created_at/expires_at
risk/action metadata for approvals
state
```

Responses include the interaction ID and idempotency key. Expired/stale interactions cannot be approved.

## 10. Automations

Observed cron model includes:

- ID/profile/name;
- prompt or script;
- skills;
- schedule expression/run-at/display;
- repeat count/completed count;
- enabled/state;
- delivery target;
- provider/model/base URL;
- agentless mode;
- context sources;
- enabled toolsets;
- working directory;
- last/next run;
- last status/error/delivery error.

Validation:

- Require at least prompt, script, or skill.
- Trim optional fields and intentionally send null when clearing them.
- Default delivery to local unless the user chooses a supported target.
- Script/no-agent jobs receive a stronger warning.
- Display schedule in server timezone and device timezone if different.
- Trigger is idempotent only if adapter supplies an operation key.

## 11. Files and attachments

The dashboard file API reports a locked root, current root/path, whether path changes are allowed, entries with size/mtime/MIME, and data-URL reads. It also supports streaming multipart upload, mkdir, and delete.

Mobile adapter requirements:

- enforce a configured root independent of user request;
- reject `..`, symlink escapes, absolute paths outside root, devices, and special files;
- use streamed binary download rather than large base64 data URLs;
- set content length/type/disposition safely;
- set upload limits;
- log metadata only;
- make delete recursive=false by default.

Chat attachment semantics must be defined separately from management file upload.

## 12. Version and compatibility policy

Maintain a checked-in matrix during implementation:

| Hermes release/commit | Chat Completions | Responses | Mobile adapter | JSON-RPC | Management |
| --- | --- | --- | --- | --- | --- |
| Deployment baseline | Contract-tested | Contract-tested if enabled | Required for P1 | Optional | Adapter-only |
| Unknown newer | Enabled conservatively | Probe/read-only | Version handshake | Disabled by default | Read-only disabled |
| Older unsupported | Health/models only | Disabled | Explain upgrade | Disabled | Disabled |

Rules:

- Stable `/v1` chat may use semantic capability probes.
- Mutations require an exact adapter major version and advertised operation.
- Server major-version mismatch blocks unsafe calls but preserves cached reading.
- Display current and tested versions in diagnostics.
- CI runs fixtures from every supported version.

## 13. Connection test stages

The in-app test returns a structured report:

1. URL syntax and HTTPS policy.
2. Network path available.
3. DNS resolution/connect attempt.
4. TLS trust and hostname validation.
5. Azure Basic Authentication.
6. Hermes `/health` response.
7. Authenticated `/v1/models` response.
8. Lightweight streaming framing check when safe.
9. `/mobile/v1/capabilities` adapter check.
10. Optional APNs relay reachability/pairing status.

Never report “wrong password” for all `401` responses blindly; distinguish edge rejection from proxy/upstream misconfiguration using a safe edge header/error code. Do not expose upstream secrets or internal addresses.

## 14. Proxy requirements checklist

- [ ] Tailnet-only listener for chat/management routes
- [ ] HTTPS with valid hostname certificate
- [ ] Basic Auth and rate limiting
- [ ] API key injection and inbound Authorization removal
- [ ] Endpoint/method allowlist
- [ ] SSE buffering disabled
- [ ] WebSocket upgrade support for adapter events
- [ ] Request/body/upload limits
- [ ] Long-turn and idle heartbeat settings
- [ ] Safe CORS policy (native app does not need permissive CORS)
- [ ] Redacted access/error logs
- [ ] Azure NSG denies direct Hermes ports
- [ ] Health endpoint that does not leak configuration
- [ ] Signed webhook egress to push relay
- [ ] Backup/recovery for Hermes state independent of the iOS app

## 15. Open integration tasks

Before coding beyond stable chat:

1. Record the deployed Hermes release/commit and Azure topology.
2. Capture `/health`, `/v1/models`, Chat Completions SSE, and Responses SSE fixtures with secrets removed.
3. Decide whether to deploy the recommended `/mobile/v1` companion adapter.
4. Extract exact JSON-RPC methods/events for the pinned release if the adapter wraps them.
5. Define edge error headers/codes for Basic versus upstream failures.
6. Define chat attachment upload and artifact download contracts.
7. Define signed event/webhook sources for APNs.
8. Add contract tests that run against a disposable Hermes instance in CI or staging.
