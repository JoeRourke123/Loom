# Welcome to Loom

Loom is an iOS automation platform. You write scripts in TypeScript, and those scripts call native
iOS APIs — networking, files, the database, notifications, health data, location, the camera, AI,
and more — through a single global object named `Loom`. Scripts run on-device, inside
JavaScriptCore. There is no server component.

Scripts as tools. Your phone, your rules.

If you know TypeScript or JavaScript, you already know most of what you need. This page orients
you to how a Loom project is put together and where to go next.

## Requirements

- iOS 27 or later
- iPhone (the app is iPhone-first)

Loom itself is built with SwiftUI and Foundation Models v2, but you don't need to know Swift to
write scripts — everything you author is TypeScript.

## How a Project Is Structured

A Loom project is a folder in `iCloud Drive/Loom/`. Because it lives in iCloud Drive, you can edit
it from Loom's built-in editor or from any external editor that can see iCloud Drive.

```
iCloud Drive/Loom/MyProject/
├── main.ts        # required — config + script logic
├── helpers.ts      # optional — sibling modules, imported by main.ts
└── secrets.json    # optional — Keychain-backed, never synced
```

- **`main.ts` is the sole source of truth.** There is no separate `loom.config.json`. Configuration
  (name, permissions, triggers, and so on) and the script's actual logic both live in `main.ts`,
  wired together through a `loom()` wrapper function.
- Loom reads that configuration statically — it extracts it from the `loom()` call without
  executing your script — so the app can show project metadata without running your code.
- **A widget is optional.** Export a function called `widget` from `main.ts` to provide one, using the same
  `loom()` wrapper pattern.
- **`secrets.json` is optional and Keychain-backed.** It holds values like API keys and is excluded
  from iCloud sync and from `.loom` exports, so secrets don't leave the device.

## The `Loom` Global

Inside a running script, `Loom` is the bridge to the rest of iOS. It's organized into namespaces
by area:

- `context`, `log`, `ui`, `notify` — script environment, logging, and UI/notifications
- `network`, `files`, `db`, `kv` — networking, file access, and storage
- `health`, `location`, `contacts`, `calendar` — device and personal data
- `camera`, `photos`, `share`, `clipboard`, `speech` — media and system interaction
- `device`, `ai` — device info and on-device/cloud AI

Each namespace is documented in detail in the API Reference. This page won't walk through
individual methods — start with **Core Concepts** and **Overview** for that.

## Permissions

Loom does not run its own permission system. When a script calls an API that touches sensitive
data or hardware — location, contacts, health, the camera, and so on — iOS shows its standard
system permission prompt the first time, exactly as it would for any other app. See
**Permissions & Privacy** for details on how this interacts with script triggers that run in the
background.

## Where to Go Next

- **New to Loom?** Start with **Getting Started** to create your first project, then
  **Your First Script** to write and run something real.
- **Want the mental model first?** Read **Core Concepts** for how projects, scripts, and the
  `Loom` bridge fit together before writing code.
- **Building something specific?** The Guides cover concrete tasks — databases, widgets, Siri and
  Shortcuts, background tasks, AI, sharing, debugging, and exporting projects.
- **Looking up a method?** The API Reference documents every `Loom.*` namespace, the `loom()`
  config shape, and the `ctx` object passed into your script.
- **Something not working?** Check Troubleshooting and Limitations before filing anything as a bug
  — some gaps (like certain APIs or platforms) are known and documented there, not oversights.

## See Also

- [Getting Started](loom-doc://getting-started/getting-started.md)
- [Core Concepts](loom-doc://getting-started/core-concepts.md)
- [Your First Script](loom-doc://guides/first-script.md)
- [Overview](loom-doc://api-reference/overview.md)
- [Troubleshooting](loom-doc://troubleshooting/troubleshooting.md)
