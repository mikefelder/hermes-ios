# Hermes Mobile Design System

## 1. Design intent

The app should feel unmistakably Hermes while remaining a first-class iOS application. Preserve the official product's dark teal canvas, warm cream content, technical/ritual character, grouped agent activity, restrained grain, and expressive status language. Use native navigation, sheets, menus, text selection, share flows, permissions, and accessibility behavior.

Do not copy screenshots pixel-for-pixel or bundle referenced artwork/fonts without verifying license and redistribution rights. Build the visual system from official public tokens and original app assets.

## 2. Upstream design anchors

Observed in the official Hermes dashboard on August 6, 2026:

- Default **LENS_0 / Hermes Teal** background: `#041C1C`.
- Primary warm midground/content: `#FFE6CB`.
- Output/data success accent: `#34D399`.
- Destructive: `#FB2C36`; success: `#4ADE80`; warning: `#FFBD38`.
- Three-layer theme model: background, midground, foreground/highlight.
- Cards use a small mix of cream into the dark canvas rather than an unrelated gray.
- Default radius is `0.5rem` and density is comfortable.
- Brand chrome can use a display/expanded type treatment; technical values use monospace.
- Brand uppercase is opt-in for chrome, never global body copy.
- Minimum upstream body text floor is 12 px equivalent; text opacity never below 0.7.
- Official dashboard supports semantic tokens, themes, density, and scoped typography.

## 3. Native color tokens

Create named colors in `Assets.xcassets` with light/dark/high-contrast variants where appropriate. The branded app defaults to dark but must still handle system contrast settings.

| Token | Default | Use |
| --- | --- | --- |
| `HermesCanvas` | `#041C1C` | Primary app background |
| `HermesSurface` | mix ≈ 4% `#FFE6CB` over canvas | Cards, message grouping |
| `HermesSurfaceRaised` | mix ≈ 7% cream over canvas | Composer, sheets, selected rows |
| `HermesTextPrimary` | `#FFE6CB` | Primary text/icons |
| `HermesTextSecondary` | cream at ≥80% effective contrast | Metadata and subtitles |
| `HermesTextTertiary` | cream at ≥70% effective contrast | Footnotes, nonessential chrome |
| `HermesBorder` | cream at ≈15% | Dividers and outlines |
| `HermesAccent` | `#FFE6CB` | Primary actions/focus |
| `HermesOnAccent` | `#041C1C` | Text on cream buttons |
| `HermesAgent` | `#34D399` | Agent activity/output, connected state |
| `HermesSuccess` | `#4ADE80` | Completed/safe status |
| `HermesWarning` | `#FFBD38` | Waiting, risky, degraded status |
| `HermesDanger` | `#FB2C36` | Failure/destructive controls |
| `HermesCodeCanvas` | near-black teal | Code and tool output |

Implementation rules:

- Use semantic colors, never raw hex in feature views.
- Dynamic states must keep at least WCAG AA contrast.
- Do not lower text opacity below 0.7; use a token designed for the role.
- Color never carries status alone; pair with symbol and label.
- Keep destructive red out of brand accents.
- Respect Differentiate Without Color and Increase Contrast.

## 4. Typography

### 4.1 Tiers

| Tier | Native style | Use |
| --- | --- | --- |
| Wordmark | custom licensed brand face or `.title2.weight(.semibold)` | “Hermes” identity only |
| Page chrome | `.largeTitle`, `.title`, `.headline` | Navigation titles and primary sections |
| Brand label | compact display/custom face, optional uppercase | Small section labels, badges, status chrome |
| Body | system San Francisco text styles | Conversation and settings copy |
| Technical | SF Mono via monospaced design | Model IDs, commands, paths, usage, schedules, code |

Rules:

- Prefer Dynamic Type styles; do not hard-code body sizes.
- Uppercase only short brand chrome. User content/model names remain unchanged.
- Use monospaced digits for token counts, durations, and changing numeric states.
- Code blocks require at least `.callout` at normal Dynamic Type and horizontal scrolling.
- If official Mondwest/Rules/Collapse fonts are desired, confirm mobile embedding license and include fallbacks; font absence must not change layout correctness.

## 5. Spacing, shape, and elevation

Base spacing scale in points: `4, 8, 12, 16, 20, 24, 32, 40`.

- Screen horizontal margin: 16 compact, 20 regular.
- Message vertical separation: 12; grouped content parts: 6–8.
- Card padding: 12 compact, 16 standard.
- Minimum tap target: 44×44.
- Default corner radius: 8; composer/cards may use 12–16 where native touch affordance benefits.
- Tool/result cards use a 1-point semantic border rather than heavy shadows.
- Sheets use system materials only when text contrast remains correct.
- Keep the warm glow/grain subtle and nonessential; remove under Reduce Transparency or low-power/performance constraints.

## 6. Iconography and imagery

- Use SF Symbols for controls and state.
- Use an original Hermes mark/app icon inspired by the caduceus/agent identity, not downloaded editorial artwork.
- Use outlined symbols at rest and filled variants for active state where standard iOS conventions support it.
- Tool icons are semantic: terminal, globe/search, document, code, image, audio, branch/delegation.
- Decorative symbols are hidden from VoiceOver.
- Generated or remote images always include a generic accessibility label until meaningful server metadata is available.

## 7. Navigation

### iPhone tab bar

- Chat — `message`
- Sessions — `clock.arrow.circlepath`
- Automations — `calendar.badge.clock`
- Settings — `gearshape`

The Chat navigation bar contains:

- active session title;
- compact connected/degraded indicator;
- model/profile subtitle or status sheet trigger;
- new conversation button;
- overflow for rename, usage, compress, share, delete.

Do not overload the tab bar with transient tasks. Background/delegated tasks appear inside Chat and Sessions.

## 8. Core components

### 8.1 Connection status pill

States:

- Connected — green agent accent, checkmark, optional latency.
- Connecting — spinner, “Connecting.”
- Offline — slash cloud, cached/read-only.
- Tailscale unavailable — network badge, open instructions.
- Unauthorized — key/lock symbol, edit credentials.
- Degraded — warning, server reachable but feature/provider failure.
- Incompatible — exclamation, version details.

The pill opens a diagnostic sheet; it never exposes the server hostname in screenshots by default.

### 8.2 Message row

User messages use a warm raised surface aligned with clear ownership. Agent messages live closer to the canvas and use the Hermes mark/status rail. Avoid oversized chat bubbles that make long technical content narrow.

Parts:

- sender/accessibility header;
- timestamp/status on demand;
- Markdown text;
- code blocks;
- attachment strip;
- tool activity group;
- artifacts;
- usage/footer actions.

Actions: copy, select text, share, retry where valid, report diagnostic (local only). Long-press must not conflict with text selection.

### 8.3 Composer

- Expanding multiline text editor, capped around 35–40% of screen.
- Attachment button opens photo/camera/file options.
- Microphone toggles recording/dictation based on chosen mode.
- Send button changes to stop only when **Stop remote work** is genuinely supported.
- While busy, sending opens or reflects redirect/queue/steer mode.
- Attachment previews show type, size, remove, upload state, and error.
- Draft is visibly retained on send failure.
- Keyboard-safe bottom placement uses safe-area inset, not geometry hacks.

### 8.4 Agent activity stack

A single collapsible card avoids flooding mobile chat:

```text
Hermes is working                       1m 24s
✓ Read 4 files
✓ Searched the web
● Running tests…
2 more steps
```

- Update rows in place by stable invocation ID.
- Default collapsed after completion; failed/risky activity remains expanded.
- Expanded rows show safe arguments, duration, result summary, and bounded output.
- Technical content uses monospace.
- Never show secrets even if upstream accidentally includes them; apply client redaction as defense in depth.

### 8.5 Approval card

Visual priority: warning border and icon, not a frightening full red screen.

Required fields:

- “Hermes needs approval”;
- action/command;
- remote location/context;
- concise risk reason;
- expiry/state;
- **Deny** and **Approve once** buttons.

High-risk actions may require Face ID/Touch ID or typed confirmation after product review. No “always approve” in v1.

### 8.6 Clarification card

- Question and optional explanatory text.
- Radio list for single select; checkbox list for multi-select.
- “Other” text field where allowed.
- Selection summary and submit button.
- Preserve choices during temporary disconnect.
- VoiceOver announces selection mode and count.

### 8.7 Code block

- Header: language/path if known and Copy.
- Horizontally scrolling, selectable monospaced content.
- Optional wrap toggle.
- Collapse very long output with line/byte count.
- Diff content uses semantic insertion/deletion colors plus `+`/`−` markers.

### 8.8 Artifact card

- Thumbnail/type symbol, filename, type/size, origin tool/session.
- Preview, download/retry, share.
- Never auto-open active content.
- External links identify destination host before leaving the app.

### 8.9 Session row

- Title and one- or two-line preview.
- Last activity, source, model.
- Running/waiting/completed marker.
- Optional tool/message counts.
- Swipe actions: rename and delete, with destructive confirmation.

### 8.10 Automation row

- Name, human schedule, next run.
- Enabled/paused/state badge.
- Last result/error.
- Context menu: run now, pause/resume, edit, delete.
- Running now requires confirmation when job is costly/destructive.

## 9. Screen specifications

### 9.1 Welcome/setup

1. Hermes mark and one-sentence value.
2. Privacy statement: “Your conversations travel directly to your private server.”
3. URL, username, password fields with examples/help.
4. Password manager support (`textContentType` where appropriate).
5. Test results list by stage.
6. Save/connect primary action.
7. Tailscale prerequisites link.

Password has reveal-while-pressed, paste support, and no autocorrect/capitalization. Screenshots/app switcher are obscured.

### 9.2 Chat empty state

Original, lightweight illustration/mark plus suggested prompts:

- “What should we work on?”
- Resume recent session.
- Launch background task.
- Check agent status.

Suggestions are contextual but never upload local data until tapped/sent.

### 9.3 Sessions

- Search field with recent/source filters.
- Sections: Active, Recent, Background, optionally Other platforms.
- Cached content shows subtle “Updated …” banner.
- Pull-to-refresh and pagination preserve scroll position.

### 9.4 Automations

- Upcoming summary at top.
- Segments: Active, Paused, Needs attention.
- Creation flow uses progressive sections rather than one dense form.
- Show server timezone prominently.

### 9.5 Settings

Sections:

- Connection
- Agent: profile, model, personality, reasoning
- Capabilities: skills, toolsets, memory status
- Notifications and privacy
- Appearance and accessibility
- Storage
- Diagnostics/about

High-impact operations are separated into an advanced area.

## 10. Motion and haptics

- Streaming text appears continuously without per-token animation.
- Tool rows crossfade/update; do not slide every event into chat.
- Use a restrained pulse for active agent state, disabled under Reduce Motion.
- Success haptic on accepted send/task completion while foreground.
- Warning haptic for approval/clarification, never repeated continuously.
- Error haptic for immediate user action failure.
- No haptic for every streamed tool event.
- Navigation uses system transitions.

## 11. Markdown and remote content safety

- Sanitize/ignore raw HTML by default.
- Links require explicit tap and use system browser or isolated in-app browser.
- Custom URL schemes require an allowlist and confirmation.
- Remote images do not receive app credentials and do not auto-fetch cross-origin tracking resources; proxy/signed artifact flow is preferred.
- Mermaid/HTML/JavaScript rendering is deferred unless placed in a hardened nonpersistent web view with no bridge.
- Code is text, never executable from the render surface.

## 12. Accessibility behavior for streaming

- Message containers have stable accessibility identities.
- Do not announce every token.
- Announce phase transitions such as “Hermes started working,” “Approval required,” and “Response complete.”
- Offer a setting to reduce progress announcements.
- Preserve VoiceOver focus when rows update.
- Expose tool rows as a summary element with expandable children.
- Use accessibility actions for Copy, Approve, Deny, Retry, Pause, and Resume.

## 13. Localization readiness

- All UI text uses string catalogs and format styles.
- No string concatenation for sentences/status.
- Dates, costs, bytes, counts, and durations use locale-aware formatters.
- Layout supports expansion and right-to-left mirroring.
- Model IDs, commands, paths, and code remain directionally isolated technical content.
- English ships first unless localization scope changes.

## 14. Design deliverables

Before feature implementation completes:

- App icon with standard/dark/tinted variants.
- Color assets and semantic Swift tokens.
- Typography and spacing tokens.
- Component preview catalog covering every state.
- iPhone compact and large Dynamic Type layouts.
- VoiceOver annotations and focus order.
- Light/high-contrast decision and examples.
- Empty/loading/error/offline/unauthorized/incompatible screens.
- Notification icons/content examples.
- Asset/font license record.

## 15. Visual QA checklist

- [ ] Matches official teal/cream identity without copying editorial art
- [ ] No feature view uses raw colors or arbitrary spacing
- [ ] Dynamic Type works through accessibility sizes
- [ ] Contrast passes in all states
- [ ] Reduce Motion/Transparency respected
- [ ] Long URLs, model names, commands, and localized strings do not clip
- [ ] Keyboard, rotation, call status bar, and safe areas handled
- [ ] Streaming does not cause scroll jumps or focus theft
- [ ] Screenshots and app switcher do not expose credential fields
- [ ] iPad layout is intentional if device family remains enabled
