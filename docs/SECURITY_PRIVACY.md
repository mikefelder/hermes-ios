# Security and Privacy Specification

## 1. Security objectives

1. Compromise of app preferences or logs must not disclose the server password or Hermes API key.
2. The Hermes runtime must not be directly internet-exposed for mobile chat.
3. Network attackers must not read or alter conversations or credentials.
4. Remote/agent content must not trigger local execution or privileged actions.
5. A stale or forged notification/deep link must not approve or execute anything.
6. A lost locked phone should receive iOS Data Protection and Keychain protection.
7. Dangerous remote actions require informed, current user consent.
8. Diagnostics and telemetry must be safe to share by construction.

## 2. Trust boundaries

```text
Untrusted/partially trusted
- User-entered URL
- Network and DNS
- Azure edge responses
- Hermes/model/tool output
- Remote files and links
- Notification payload IDs/content
- Imported attachments

Trusted only after verification
- Tailscale identity/connectivity
- TLS server identity
- Azure Basic Auth result
- Signed push relay events
- Hermes/mobile-adapter capability contract

High-value secrets
- User password
- Hermes API_SERVER_KEY (server only)
- APNs provider signing key (relay only)
- Device registration/pairing secret
- APNs device token
- Provider/tool credentials stored by Hermes
```

The language model and tool output are never a trusted authority for approval, navigation, authentication, or local code execution.

## 3. Threat model

| Threat | Example | Required controls |
| --- | --- | --- |
| Credential theft at rest | Preferences backup exposes password | Keychain `ThisDeviceOnly`; no secret in SwiftData/UserDefaults/files |
| Credential leakage in transit | Basic Auth over HTTP | HTTPS required; ATS; no insecure production override |
| Header leakage | Redirect sends auth to another host | Origin-bound auth; reject cross-origin redirect |
| Brute force | Tailnet peer guesses password | Strong password, edge rate limiting, Tailscale grants, audit events |
| API-key extraction | Device compromise exposes the Hermes key | Keychain `ThisDeviceOnly`; tailnet grants limit reach; rotate in Key Vault and app together. A Basic-to-Bearer edge, where deployed, keeps the key off the phone entirely |
| Direct API exposure | Port 8642 reachable from internet | Loopback bind, no public Azure ingress on the API port, tailnet-only `tcp:8443` grant |
| Prompt injection | Tool output says “approve this URL” | Structured interaction protocol; prose cannot create approvals |
| Unsafe remote command | Agent requests destructive shell action | Explicit approval card, risk/cwd, no persistent auto-approve |
| Malicious artifact | HTML/PDF/file exploits viewer | MIME/size validation, Quick Look/system viewer, no active web content |
| Tracking resource | Markdown image leaks IP/auth | No credential forwarding; disable arbitrary remote auto-load |
| Notification spoof/replay | Deep link approves expired command | IDs only; authenticate/refetch; expiry/idempotency; no direct action |
| Duplicate request | Reconnect resends expensive/destructive prompt | Idempotency key or uncertain-state reconciliation |
| Local shoulder surfing | App switcher shows private chat | Privacy mode snapshot cover; generic notifications |
| Log/crash leakage | Prompt or path captured | Metadata-only OSLog, privacy annotations, redacted diagnostics |
| Compromised push relay | Reads conversations or controls Hermes | Minimal metadata; no Hermes creds; relay cannot call agent actions |
| Version skew | Changed internal endpoint performs wrong mutation | Capability/version gating; exact contract tests for mutations |
| SSRF/path traversal | User/artifact path reaches server internals | Companion-adapter URL/path allowlists and locked file root |

## 4. Credential storage

### 4.1 Server profile

Non-secrets:

- profile UUID and optional display name;
- normalized server URL;
- username;
- timestamps and capability metadata.

Secrets:

- password only.

Store password as a generic Keychain item:

- service: bundle identifier + `.server-credential`;
- account: server profile UUID;
- synchronizable: false;
- accessibility: `AfterFirstUnlockThisDeviceOnly` only if an approved background operation needs it, otherwise `WhenUnlockedThisDeviceOnly`;
- access group: app-only unless a future extension is reviewed.

Do not store the password in an `Observable` object longer than necessary. Credential-edit UI uses a temporary buffer and clears it after save/cancel/background.

### 4.2 Password editing semantics

- A saved password is represented as “Password saved,” not fake bullets that imply the actual value is loaded.
- Leaving the password field untouched keeps the Keychain item.
- Entering a new value replaces it only after successful save.
- “Remove saved password” is an explicit action.
- Connection test with proposed credentials uses an ephemeral session.
- Forget server deletes Keychain item, cookies/tickets, push pairing, cache, downloads, and drafts.
- Keychain deletion failure is surfaced and retried; never report a successful forget while a secret remains.

### 4.3 Password manager

Use appropriate iOS text content types and associated domains only if a real, controlled web credential domain exists. Never claim Password AutoFill association for a `ts.net` host not controlled for that purpose.

## 5. Authentication architecture

### 5.1 Mobile-to-edge

- HTTP Basic with user-entered username/password over HTTPS.
- Authentication header attached only to the configured scheme/host/port and intended base path.
- Handle challenge-based authentication; preemptive header only when required and origin-bound.
- Reject URL values containing `user:password@host`.
- Do not persist response cookies unless a documented adapter requires them.
- Treat `401` as credentials/session failure and `403` as authorization failure.

### 5.2 Edge-to-Hermes

- Edge removes inbound Authorization.
- Edge injects `Bearer API_SERVER_KEY` from server secret storage.
- Hermes key should be random, rotated, and scoped to the instance.
- Edge logs never record Authorization or request/response bodies.
- Prefer separate upstream credentials/scopes for management adapter if supported.

### 5.3 Dashboard/mobile adapter

Do not reuse the dashboard's HTML-injected ephemeral token by scraping. A companion adapter should issue:

- short-lived session/access token after Basic Auth, or continue edge-authenticated requests;
- single-use, ≤30-second WebSocket tickets;
- explicit scopes such as `chat`, `read`, `manage`, `approve`, `admin`;
- revocable device pairing ID for push.

A token in a WebSocket query must be single-use and omitted from logs.

## 6. Transport security

- Production supports `https`/`wss` only.
- No `NSAllowsArbitraryLoads` and no broad ATS exceptions.
- Never implement trust-all certificate delegates.
- System trust is preferred over custom certificate pinning; if pinning is adopted, define rotation and backup pins first.
- Reject TLS hostname mismatch, expired/untrusted certificate, weak protocol negotiation, and cross-host redirects.
- Display certificate errors as certificate errors, not password errors.
- Set request/body/time limits and bounded retries.
- Retry only idempotent operations automatically.
- Avoid credentials in URLs/query strings.

A debug-only plain-HTTP mode may exist only behind compile-time `DEBUG`, a prominent warning, loopback/private-address validation, and no production entitlement/config path.

## 7. Tailscale and Azure controls

- Tailnet ACL/grants restrict the user/device to the mobile edge service.
- Use device posture requirements if available and appropriate.
- Azure NSG denies public ingress to Hermes and adapter ports.
- Proxy binds to tailnet/private interface, not `0.0.0.0` public exposure unless another locked-down private ingress fronts it.
- SSH/administration ports are separate from app traffic.
- Enable Azure disk encryption and least-privilege managed identity.
- Store edge and APNs secrets in Azure Key Vault or equivalent.
- Keep Hermes state backups encrypted and access-controlled.
- Audit authentication, pairing, and admin actions without content.

Tailscale being connected does not prove that a responding host is the intended Hermes service; TLS and application authentication remain mandatory.

## 8. Authorization and dangerous actions

Roles/scopes should separate:

- chat/send/stop;
- read sessions/artifacts/status;
- answer clarification;
- approve commands;
- manage automations/skills/toolsets/models;
- admin operations.

For every mutation:

- capability and scope check;
- server profile/session identity check;
- CSRF protections where cookie auth exists;
- idempotency key;
- clear confirmation for destructive/high-cost effects;
- post-action fetch to verify state.

Approvals:

- only originate from a signed/authenticated structured event;
- show exact normalized action, cwd/host context, reason, and expiry;
- default action is deny/cancel;
- “Approve once” only in v1;
- bind response to interaction, session, server, and turn IDs;
- reject already-resolved/expired requests;
- never approve from notification actions without opening/authenticating the app;
- optionally require LocalAuthentication for high-risk classes.

## 9. Remote content handling

### Markdown

- Raw HTML disabled/sanitized.
- No script, iframe, embedded object, CSS, or arbitrary WebView bridge.
- `javascript:`, `data:` (except internally generated validated image data), file, and unknown schemes blocked.
- External HTTPS links show destination and require user tap.
- Links never inherit app Authorization/cookies.

### Files

- Enforce size limits before and during transfer.
- Validate extension, declared MIME, and inspected UTType where possible.
- Randomize local storage name and retain display name separately.
- Prevent path traversal and symlink escape server-side.
- Quarantine/Quick Look behavior relies on iOS system handling; no local execution.
- Do not auto-extract archives.
- Auto-delete cached artifacts by retention/space policy.

### Images/audio/video

- Strip photo metadata from re-encoded uploads by default.
- Require camera/microphone/photo permission only at point of use.
- Stop recording on interruption/background and make state obvious.
- Never start microphone recording due to remote content or notification.

## 10. Local data protection

- SwiftData/local files are caches, not the only copy.
- Apply `NSFileProtectionComplete` where practical; document exceptions needed for background operations.
- Store downloads under Application Support/Caches, excluded from backup unless user-created data requires otherwise.
- Store temporary attachments with protected files and remove after upload/cancel/expiry.
- Clear pasteboard only if the app placed known sensitive data and iOS behavior permits without surprising the user.
- Privacy mode overlays app content when inactive; credential screens always cover.
- Optional Face ID app lock may be P2; it supplements device lock and does not encrypt server data by itself.

## 11. Push security

The public relay receives no URL username, password, Hermes API key, prompt, response, reasoning, tool arguments, or remote file content.

Allowed default event fields:

```text
pairing_id
opaque server_alias
opaque session/task/interaction ID
event category
coarse status
timestamp/expiry
collapse/thread identifiers
optional generic display title
```

- Hermes/adapter signs webhook body with HMAC and timestamp/nonce.
- Relay rejects stale/replayed/invalid events.
- Pairing uses a one-time short-lived code and app-generated secret/proof.
- Device tokens are encrypted at rest and removable.
- APNs payload defaults to generic text.
- Notification opens app, authenticates, and fetches live state before action.
- See [Push Notifications](PUSH_NOTIFICATIONS.md).

## 12. Logging, analytics, and crash reporting

Production logs must not contain:

- credentials/tokens/cookies;
- server URL, hostname, IP, username;
- prompts, responses, reasoning;
- tool arguments/results, commands, paths;
- filenames or attachment content;
- push payload/body/device token.

Use generated aliases and categories. For HTTP log method + endpoint family, response class, duration, bytes—not full URL/query/body.

No third-party analytics in v1. Before adding crash/analytics SDKs:

- complete data-flow/privacy review;
- disable automatic network breadcrumbs and view text capture;
- filter attachments and custom keys;
- update privacy manifest and App Store privacy answers;
- provide opt-out where appropriate.

## 13. Privacy manifest and permissions

Expected usage descriptions only when implemented:

- Microphone — recording voice messages/dictation.
- Speech recognition — transcription if Apple Speech is used.
- Camera — attach a new photo.
- Photo library add/read — use limited picker where possible; PHPicker often avoids broad read permission.
- Notifications — completion and action-required alerts.

Also review required-reason APIs and privacy manifest declarations for preferences, file timestamps, disk space, and other accessed APIs at implementation time.

Permission prompts must be preceded by in-app context and denial must leave text chat functional.

## 14. Data lifecycle

| Data | Location | Retention | Deletion |
| --- | --- | --- | --- |
| URL/username/profile | app preferences | until profile forgotten | Forget server |
| Password | Keychain, device-only | until replaced/forgotten | Remove password/Forget server |
| Session/message cache | protected local store | configurable, default bounded | Storage settings/Forget server |
| Drafts | protected local store | until sent/discarded or retention expiry | Composer/storage/Forget server |
| Downloaded artifacts | protected cache | LRU + age/size bound | Automatic/manual/Forget server |
| APNs token/pairing | app + relay | until unregister/expiry | Disable notifications/Forget server |
| Hermes source data | Azure Hermes state | controlled by operator | Hermes/server controls |
| Relay event metadata | Azure relay | minimal operational window | automatic TTL |

Remote deletion semantics must be clearly separate from clearing local cache.

## 15. Security testing requirements

- Keychain persistence/deletion/accessibility tests on device.
- Inspect app container and defaults to prove password absence.
- Proxy/redirect tests proving Authorization never crosses origin.
- ATS/TLS failure tests.
- Fuzz SSE, JSON, Markdown links, deep links, file names, and notification payloads.
- Replay/idempotency tests for sends, approvals, and push webhooks.
- Path traversal/symlink/upload bomb tests on companion adapter.
- Log and diagnostics secret-canary scan.
- Static dependency/CVE/license review.
- Threat-model review before enabling management mutations.
- External penetration review before public/App Store distribution if feasible.

## 16. Incident and rotation plan

### Suspected password compromise

1. Change/revoke edge credential.
2. Invalidate sessions/tickets and push pairing.
3. Review auth audit events.
4. Update password in app and retest.

### Hermes API key compromise

1. Rotate `API_SERVER_KEY` server-side.
2. Restart/reload gateway.
3. No app update is required because edge injects it.
4. Review direct-port exposure and proxy logs.

### APNs key compromise

1. Revoke key in Apple Developer account.
2. Rotate Key Vault secret and relay deployment.
3. Review relay access logs; Hermes credentials remain unaffected.

### Device loss

1. Revoke Tailscale device.
2. Revoke edge user credential and push pairing.
3. Use device MDM/Find My capabilities where available.
4. Rotate credentials if lock state is uncertain.

## 17. Release security gate

- [ ] Threat model reviewed against deployed topology
- [ ] No production HTTP/ATS bypass
- [ ] Password only in Keychain and deletion verified
- [ ] Hermes API key absent from app and relay
- [ ] Direct Hermes ports not publicly reachable
- [ ] Basic Auth header origin/redirect tests pass
- [ ] Structured approval protocol; no prose parsing
- [ ] Push events signed, replay-protected, minimal
- [ ] Logs/diagnostics pass secret-canary scan
- [ ] Remote files/links sanitized and bounded
- [ ] Privacy manifest, permissions, and App Store disclosures accurate
- [ ] Supported-version mutation contract tests pass
- [ ] Dependency vulnerabilities and licenses reviewed
