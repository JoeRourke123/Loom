# ADR-010: In-app docsite — MarkdownUI + bundled Markdown + native diagram views
Date: 2026-08-01
Status: accepted

## Context
Loom needs an in-app documentation site (API reference, guides, troubleshooting) reachable from the sidebar, with decent formatting (headings, code blocks, tables) and a handful of architecture diagrams. Two open questions drove real trade-offs:

1. **Markdown rendering.** Foundation's `AttributedString(markdown:)` handles inline styling but not fenced code blocks, tables, or images distinctly — inadequate for API reference pages that lean on parameter tables and TypeScript snippets. The alternative to a rendering library is hand-rolling a Markdown parser, which is exactly the kind of fragile, ongoing-maintenance code this project avoids elsewhere (it already reaches for GRDB over raw SQLite3, Runestone over a hand-built text view).
2. **Diagrams.** A few architecture diagrams add real value (execution flow, widget data flow, Siri/intents flow, bridge architecture). Options considered: (a) bundle `mermaid.js` and render via `WKWebView`, matching the existing pattern of bundling vendor JS for the script engine (`Vendors/*.js`); (b) hand-author a small, fixed set of native SwiftUI diagram views.

## Decision
- **MarkdownUI** (`gonzalezreal/swift-markdown-ui`) for rendering. It parses and renders GFM Markdown (tables, code blocks, images, task lists) in one `Markdown(text)` call — less integration code than parsing with `apple/swift-markdown` and hand-writing a SwiftUI renderer on top of the AST, and far less than a hand-rolled parser. Added as an SPM dependency the same way GRDB and Runestone already are.
- **No syntax highlighting** in rendered code blocks (plain monospaced) — MarkdownUI supports plugging in a highlighter, but the docs are short TS/JS snippets where highlighting is a nice-to-have, not a comprehension requirement.
- **Native SwiftUI diagram views**, not Mermaid+WebView. The doc set has a small, fixed number of diagrams (4) known up front — not an open-ended authoring surface for arbitrary future diagrams. A WebView pipeline (bundle mermaid.js, build a `UIViewRepresentable`, theme it for light/dark, handle JS↔Swift sizing) is more moving parts than four hand-drawn `HStack`/`Path` box-and-arrow views, and avoids fetching/bundling a third-party JS asset for a bounded, known need.

## Consequences
- One new SPM dependency (`MarkdownUI`) to track for updates, same category of maintenance as GRDB/Runestone already carry.
- Diagrams are hardcoded Swift views, not authored from a text description — adding a 5th diagram later means writing a new SwiftUI view, not just dropping in a Mermaid block. Acceptable given the doc set's diagram needs are small and mostly architectural (unlikely to grow much); revisit with a Mermaid+WebView approach only if the diagram count grows past what hand-authoring comfortably covers.
- No full-text doc search — `.searchable` filters on title only. Fine at ~35 pages; would need a real index (or on-device search framework) if the doc set grows an order of magnitude.
