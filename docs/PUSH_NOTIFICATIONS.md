# Push Notification Specification

## 1. Why a relay is required

An iOS app cannot keep a Hermes SSE/WebSocket connection alive indefinitely after suspension. Apple Push Notification service (APNs) requires an internet-reachable provider, while the Hermes instance should remain private on Tailscale.

Therefore:

- chat and management traffic travel directly from the app to the private tailnet endpoint;
- Hermes sends minimal signed events outbound to a public Azure relay;
- the relay sends APNs notifications;
- opening a notification causes the app to reconnect privately and fetch authoritative details.

APNs is a signal, not a durable source of truth. Notifications may be delayed, coalesced, or dropped.

## 2. Architecture

```text
                          private data plane
 iPhone + Tailscale  <----------------------------> Azure edge -> Hermes
       |
       | public HTTPS registration
       v
 Azure Push Relay <---------------- signed webhook/event ---------------- Hermes adapter
       |
       | HTTP/2 APNs token authentication
       v
      APNs  ------------------------> iPhone
```

The push relay must not have network access to the private Hermes API and must not possess the user's Hermes URL, username, password, or `API_SERVER_KEY`.

## 3. Components

### iOS app

- Requests notification authorization after contextual education.
- Registers for remote notifications.
- Converts the APNs device token to bytes/hex only for transport; never logs it.
- Initiates pairing through the authenticated private mobile adapter.
- Registers/revokes the resulting pairing at the public relay.
- Stores pairing metadata in Keychain/protected settings.
- Routes notification deep links and refreshes authoritative state.
- Maintains a local notification inbox for reconciled events.

### Hermes mobile adapter

- Authenticates app through the Azure edge.
- Creates and revokes push pairing identities.
- Maps server session/task/interaction IDs to opaque relay-safe IDs or accepts that opaque IDs are already safe.
- Emits allowlisted events.
- Signs each relay webhook.
- Keeps the relay webhook secret server-side.
- Maintains a short durable event/outbox ledger for retries and app reconciliation.

### Azure Push Relay

- Internet-reachable HTTPS service with a narrow API.
- Validates pairing proof and signed Hermes events.
- Stores encrypted APNs device token, pairing ID, preferences, environment, and timestamps.
- Applies deduplication, collapse, expiry, and rate limits.
- Sends APNs with token-based provider authentication.
- Removes invalid/unregistered tokens.
- Retains minimal logs/metrics and short-lived event metadata.

## 4. Apple setup

Required project/developer configuration:

- Enable **Push Notifications** capability.
- Add `aps-environment` entitlement through signing configuration.
- Enable **Background Modes > Remote notifications** only if silent content refresh is justified; visible notifications do not require background refresh mode.
- Create an APNs signing key (`.p8`) or use a managed provider credential.
- Store key ID, team ID, bundle topic, and private key only in Azure Key Vault/relay configuration.
- Use development APNs for debug builds and production APNs for TestFlight/App Store.

Expected topic: app bundle identifier for the relevant environment, for example `com.example.hermes`.

No Notification Service Extension is required for generic notifications. Add one only if a reviewed encrypted-rich-content design needs it.

## 5. Authorization UX

Do not prompt on first launch. Recommended sequence:

1. User establishes a working Hermes connection.
2. App explains: “Allow Hermes to notify you when long-running work finishes or needs your input.”
3. User chooses **Enable notifications** or **Not now**.
4. Request system authorization for alert, sound, and badge.
5. If denied, show non-blocking settings guidance and keep all foreground features functional.

Provisional authorization is optional and should be product-tested rather than assumed.

## 6. Pairing protocol

### 6.1 Preconditions

- Working authenticated private connection.
- App has an APNs device token or can wait for one.
- Mobile adapter and relay advertise compatible protocol versions.
- Device has an app-generated installation ID stored `ThisDeviceOnly`; do not use IDFA/IDFV as identity.

### 6.2 Flow

1. App generates a random device public identifier and optional key pair/secret in Keychain.
2. App calls private `POST /mobile/v1/push/pair` with device public ID and desired categories.
3. Adapter creates:
   - random `pairing_id`;
   - one-time `pairing_token` with ≤10 minute TTL;
   - per-pairing webhook signing secret or key reference;
   - relay registration URL and protocol version.
4. Adapter stores only what it needs to emit events and returns the one-time token to the app.
5. App calls public `POST /v1/devices/register` with pairing token, APNs token, environment, app version, locale, and preferences.
6. Relay validates the token with a signed self-contained proof or one-time registration record established server-to-server. It consumes the token exactly once.
7. Relay returns a revocable `registration_id` and short confirmation.
8. App confirms registration to the private adapter.
9. App discards the one-time token and stores `pairing_id`/`registration_id` metadata.

Avoid a relay callback into the private tailnet. Use a signed pairing token or outbound server registration.

### 6.3 Token rotation

`didRegisterForRemoteNotificationsWithDeviceToken` may return a changed token at any launch. The app compares it to its protected stored value and updates the relay using a pairing-authenticated operation.

On `410 Unregistered` or applicable APNs invalid-token response, relay deletes the token and marks pairing unregistered. App can repair registration on next foreground.

### 6.4 Revocation

Trigger revocation when:

- user disables notifications;
- user forgets server;
- server connection profile is replaced;
- device/pairing is revoked by operator;
- account/password is revoked where policy requires;
- token remains invalid beyond retry window.

Best effort order: revoke private adapter pairing, revoke relay registration, clear local pairing. If offline, persist a tombstone and retry; local UI must still consider pairing disabled immediately.

## 7. Relay API sketch

All shapes are versioned and bounded. Values below are conceptual.

### Register device

```http
POST /v1/devices/register
Content-Type: application/json

{
  "pairing_token": "one-time-signed-value",
  "installation_id": "opaque-random-id",
  "apns_token": "hex-token",
  "apns_environment": "development",
  "bundle_id": "com.example.hermes",
  "app_version": "1.0",
  "locale": "en-US",
  "preferences": {
    "completion": true,
    "failure": true,
    "approval": true,
    "clarification": true,
    "automation": true,
    "content_preview": false
  }
}
```

Response:

```json
{
  "registration_id": "opaque-id",
  "pairing_id": "opaque-id",
  "protocol_version": 1,
  "registered_at": "2026-08-06T12:00:00Z"
}
```

### Update token/preferences

```text
PUT /v1/devices/{registration_id}
```

Requires a pairing-bound proof/token, not Basic/Hermes credentials.

### Revoke

```text
DELETE /v1/devices/{registration_id}
```

Idempotent; returns success even if already removed.

### Ingest Hermes event

```http
POST /v1/events
X-Hermes-Pairing: <pairing-id>
X-Hermes-Timestamp: <unix-seconds>
X-Hermes-Nonce: <random>
X-Hermes-Signature: v1=<HMAC-SHA256>
Content-Type: application/json

{
  "event_id": "opaque-id",
  "type": "turn.completed",
  "server_alias": "opaque-id",
  "session_id": "opaque-id",
  "task_id": "opaque-id-or-null",
  "occurred_at": "2026-08-06T12:00:00Z",
  "expires_at": "2026-08-07T12:00:00Z",
  "status": "completed"
}
```

Signature covers version marker, timestamp, nonce, and exact raw body. Relay rejects timestamps outside a small window and stores nonce/event ID through the replay window.

## 8. Event catalog

| Event | Default | Interruption | Deep link | Collapse key |
| --- | --- | --- | --- | --- |
| `turn.completed` | On | active | Session | session/turn |
| `turn.failed` | On | active | Session | session/turn |
| `interaction.approval_required` | On | time-sensitive only after review | Interaction | interaction ID |
| `interaction.clarification_required` | On | active | Interaction | interaction ID |
| `background.completed` | On | active | Background session | task ID |
| `background.failed` | On | active | Background session | task ID |
| `automation.completed` | On | passive/active preference | Automation/session | job/run ID |
| `automation.failed` | On | active | Automation | job/run ID |
| `agent.long_running` | Off | passive | Session | session/turn |
| `gateway.degraded` | Off/P2 | passive | Diagnostics | server |

Critical Alerts are out of scope. Time Sensitive notifications must be limited to genuinely expiring approvals and follow Apple policy/user preference.

## 9. APNs payload

Default privacy-preserving payload:

```json
{
  "aps": {
    "alert": {
      "title": "Hermes",
      "body": "Your task is complete."
    },
    "sound": "default",
    "thread-id": "serverAlias.sessionAlias",
    "category": "HERMES_TURN_COMPLETE",
    "badge": 1
  },
  "v": 1,
  "event": "turn.completed",
  "server": "opaque-alias",
  "session": "opaque-id",
  "event_id": "opaque-id"
}
```

Requirements:

- Stay well under APNs payload limit.
- No prompt, response, tool output, command, file path, username, server URL, or credential.
- Opaque IDs have strict length/character validation.
- `apns-expiration` reflects event expiry.
- `apns-collapse-id` coalesces duplicate/progress updates.
- `apns-priority` 10 for user-visible actionable/completion alerts; 5 for background content updates where used.
- `thread-id` groups by server/session without exposing names.
- Badge represents local unread notification inbox, not raw number of APNs sends.

Optional content previews are deferred until a separate end-to-end encrypted design. TLS to a trusted relay alone does not satisfy the privacy goal for rich content.

## 10. Notification categories and actions

Recommended categories:

- `HERMES_TURN_COMPLETE`: Open, Dismiss.
- `HERMES_TURN_FAILED`: Open, Dismiss.
- `HERMES_INTERACTION_REQUIRED`: Open, Dismiss.
- `HERMES_AUTOMATION`: Open, Dismiss.

Do not include **Approve** or **Deny** direct notification actions in v1. Approval requires app unlock, authenticated refresh, exact action display, and expiry validation.

A future **Stop** action also requires a carefully scoped background authorization token and server reachability; defer it.

## 11. Deep-link handling

On notification tap:

1. Parse only known payload version/category and bounded opaque IDs.
2. Select matching configured server alias; if absent, explain that the server was removed.
3. Wait for protected data and app setup.
4. Require device unlock/LocalAuthentication if app privacy lock is enabled.
5. Connect via Tailscale/private API and authenticate normally.
6. Fetch event/session/interaction state.
7. Ignore stale, resolved, missing, or unauthorized IDs with a clear message.
8. Navigate to live data; never trust notification body as state.

If Tailscale is disconnected, show cached generic event and instructions/retry. Do not send app credentials through the relay to fetch details.

## 12. Foreground behavior

When a notification arrives while app is foreground:

- reconcile event into local inbox;
- update relevant active session/task;
- show an in-app banner instead of a duplicate system interruption where appropriate;
- produce haptic according to user preference;
- deduplicate by `event_id` against stream-received completion.

SSE/WebSocket and APNs may report the same event. Stable event IDs are mandatory for clean deduplication.

## 13. Background/silent notifications

Silent `content-available` pushes are opportunistic, throttled, and not guaranteed. Do not depend on them for correctness.

If enabled:

- use only to refresh minimal metadata/inbox;
- finish within system budget;
- do not initiate long agent streams;
- use credentials only if Keychain accessibility permits and privacy review approves;
- call the completion handler promptly;
- visible approval/failure notifications remain the primary signal.

Background processing tasks are not a substitute for APNs and are unlikely to run at exact task completion times.

## 14. Relay data model

### Device registration

```text
registration_id
pairing_id
installation_id_hash
encrypted_apns_token
apns_environment
bundle_id
preferences
created_at/updated_at/last_success_at
invalidated_at
```

### Pairing key

```text
pairing_id
webhook_secret_encrypted or key reference
server_alias
allowed_event_types
created_at/revoked_at
```

### Event deduplication

```text
event_id
pairing_id
received_at
expires_at
delivery_status/attempt_count
apns_reason_category
```

Use TTL deletion. Do not store notification body beyond delivery needs; bodies are generic and can be generated from event type.

## 15. Delivery and retry policy

- Validate and persist deduplication marker before send.
- Retry transient APNs 429/5xx/network failures with exponential backoff and jitter until event expiry.
- Honor `Retry-After`.
- Do not retry invalid token/topic/payload indefinitely.
- Remove token on `410` and appropriate invalid-token responses.
- Bound attempts and queue size per pairing.
- Acknowledge Hermes event after durable acceptance, not necessarily APNs success.
- Hermes adapter uses an outbox with idempotent `event_id` and retries relay delivery.

At-least-once webhook plus APNs collapse/deduplication is acceptable. The app must tolerate duplicate notifications.

## 16. Notification preferences

Per server/device:

- task completions;
- failures;
- approvals;
- clarifications;
- automation results;
- long-running heartbeats;
- sound;
- badge;
- quiet hours;
- generic versus future encrypted preview.

System notification settings remain authoritative. The app should show their current authorization state and deep-link to Settings when denied.

## 17. Relay observability

Metrics without content:

- registration/revocation counts;
- accepted/rejected webhook counts by reason;
- APNs success/transient/permanent failure counts;
- delivery latency histogram;
- queue depth/age;
- invalid token count;
- replay/signature failures;
- per-pairing rate-limit events using rotating aliases.

Alerts:

- sustained APNs auth failures;
- queue age above threshold;
- signature rejection spike;
- Key Vault/access failure;
- high invalid-token rate after release.

Logs never include APNs token, signature secret, raw body, server identity, or user content.

## 18. Testing matrix

- Simulator foreground local notification routing.
- Physical devices for APNs development and TestFlight production environments.
- Permission states: not determined, provisional, authorized, denied.
- APNs token initial registration and rotation.
- Pair, update preferences, revoke, forget server, reinstall.
- Valid/invalid/expired/replayed webhook signatures.
- Duplicate and out-of-order events.
- App foreground/background/terminated.
- Tailscale connected/disconnected on notification open.
- Deleted/resolved/expired interaction.
- Wrong environment/topic/token and APNs 410/429/5xx.
- Quiet hours, badge reconciliation, Focus modes, notification summaries.
- Relay outage and Hermes outbox recovery.

## 19. Push release gate

- [ ] Apple entitlement/provisioning verified on physical device
- [ ] Development and production APNs environments separated
- [ ] APNs key held only in Key Vault/relay
- [ ] Pairing is one-time, expiring, revocable, and replay-safe
- [ ] Hermes credentials absent from relay and payload
- [ ] Webhook signatures and nonce/timestamp replay protection tested
- [ ] Generic notification content is default
- [ ] Deep links fetch authenticated live state before action
- [ ] Duplicate stream/APNs events deduplicate
- [ ] Invalid tokens are removed
- [ ] Retry queue is bounded and observable
- [ ] Notification denial leaves app fully usable
- [ ] Privacy disclosure and preferences match implementation
