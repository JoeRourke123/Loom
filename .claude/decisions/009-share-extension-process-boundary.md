# ADR-009: Share Extension process boundary — App Group + loom:// handoff
Date: 2026-08-01
Status: accepted (decision locked; Group 6 implementation still pending — see below)

## Context

`Loom.share.input()` (deferred from M4, per its pre-flight decision "Loom.share → deferred to M5") needs the iOS Share Sheet to be able to hand content to a Loom project's script. Sharing into an app from the system Share Sheet requires a genuinely new Xcode target (`PBXNativeTarget`) — a Share Extension — which is a manual/Xcode-GUI step (File → New → Target), not something achievable through file edits alone, matching the same class of step M1's entitlements and M6's widget extension target required.

Two questions this target's design has to answer:
1. Does the extension get its own iCloud entitlement to read/write project files directly, or does it need something else?
2. How does the extension, once the user has picked a project and content, actually get `ScriptRunner` (which only ever runs in the main app process — see ADR-004's established rule that App Intents/interactive actions fire in the main app, never an extension) to execute?

## Decision

- **The extension gets zero iCloud entitlements.** It reuses the App Group (`group.uk.co.joerourke.loom`) M6 already introduced for the widget extension — needed anyway for staging image payloads too large to pass as a URL query parameter. App Groups and iCloud container access are orthogonal Apple entitlements; nothing about sharing requires the extension to touch the iCloud container directly.
- **Handoff rides the `loom://` URL scheme**, not a bespoke IPC mechanism. The extension calls `NSExtensionContext.open(URL(string: "loom://share?project=...&type=...")!)`; `DeepLinkHandler` (built for `loom://run` in Group 3) gets a `loom://share` branch that resolves the payload (inline for short text/URLs, a staged App Group file for images or long text) and calls `ScriptRunner.shared.run(project:trigger: .shareSheet, input:)` — the same headless, notification-reporting pattern already established for URL-scheme runs.
- **The project picker lives inside the extension itself** (mirrors M6's `SelectProjectIntent` UX — pick before handoff, not after), reading the project list from a new App Group key (`loom.allProjects`, all projects) distinct from M6's `loom.projects` (widget-enabled projects only) to avoid any collision regardless of which milestone's App Group writes land first in a given build.

## Consequences

- **Zero new cross-process infrastructure.** The extension→app path reuses two things that already exist and are already proven: the App Group and the URL scheme handler.
- **Image/long-text payloads get staged, not inlined.** A URL query parameter has practical length limits; anything over ~1500 characters (or any image) is written to the App Group container and referenced by a token instead.
- **This ADR documents a locked decision, not a shipped feature.** Group 6 (the extension target itself, `ShareViewController`, `Loom.share`'s `ShareBridge`, and the `loom://share` handler branch) is not yet implemented — it's blocked on the Xcode-GUI target-creation step, which needs to happen before this design can be built against. Written now, ahead of that code, matching this project's own convention of writing ADRs before implementation where possible.
