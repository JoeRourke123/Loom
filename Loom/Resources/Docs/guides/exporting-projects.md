# Exporting & Importing Projects

> **Status: planned, not yet available.**

This guide describes the intended design for project export/import. Nothing
below is callable from a script or reachable from the UI yet — treat it as a
preview of what's coming, not a reference for current behavior.

## Why export/import at all

Projects already live as folders in `iCloud Drive/Loom/`, so they sync
between your own devices automatically. Export/import is for the cases
iCloud sync doesn't cover:

- Sharing a project with someone else, or posting it publicly
- Keeping an offline backup outside iCloud
- Moving a project into or out of Loom by hand (email attachment, AirDrop,
  a file manager)

## The `.loom` format

A `.loom` file is planned to be a ZIP archive of a project folder. The
intended contents:

| Entry | Included | Notes |
|-------|----------|-------|
| `main.ts` | Always | The project's script and `loom()` config |
| other `.ts` files | If present | Sibling modules imported by `main.ts` |
| Other project assets | If present | Images, data files, and similar assets stored alongside the script |
| `secrets.json` | **Never** | Keychain-backed values are excluded from every export, with no option to include them |

The `secrets.json` exclusion isn't a setting — it's unconditional. Exporting
a project that uses `Loom.context` secrets will produce a `.loom` file that
runs, but without those values populated. Anyone importing the file will
need to supply their own secrets before the script can use them.

## Intended workflow

**Export:**

1. From a project, choose export.
2. Loom zips the project folder (minus `secrets.json`) into a `.loom` file.
3. Share it via the standard iOS share sheet — AirDrop, Files, Mail, etc.

**Import:**

1. Open a `.loom` file (from Files, an email attachment, AirDrop, or
   similar).
2. Loom unzips it into a new project folder under `iCloud Drive/Loom/`.
3. If the project declares secrets it needs, you'll be prompted to fill
   them in before running it — since `secrets.json` never travels with the
   export.

## Current limitations

- Export and import are not implemented. There's no export action in the
  UI and no way to open a `.loom` file yet.
- Until this ships, moving a project between devices means relying on
  iCloud Drive sync, or copying the project folder manually.
- Nothing here is scriptable — this isn't a `Loom.*` API and isn't planned
  to be one. Export/import is a UI-level operation, not something a
  `main.ts` script triggers on itself.

## See Also

- [Getting Started](loom-doc://getting-started/getting-started.md)
- [Core Concepts](loom-doc://getting-started/core-concepts.md)
- [Permissions & Privacy](loom-doc://guides/permissions-privacy.md)
- [Sharing Into Loom](loom-doc://guides/share-extension.md)
- [Limitations](loom-doc://troubleshooting/limitations.md)
