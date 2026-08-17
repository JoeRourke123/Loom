import Foundation

// Curated, hand-written index of the Loom.* JS bridge surface — feeds the editor's suggestion
// pills (LoomAPICatalog.matches) and the authoring assistant's system prompt (promptManifest).
//
// Hand-written because there is no manifest to derive one from: the real API is ~74 scattered
// setObject(_:forKeyedSubscript:) string literals across 18 files in Loom/Bridge/*.swift, and
// the api-reference/*.md docs split across two incompatible styles where only about half the
// methods carry an extractable signature block. This file is the closest thing to ground truth
// that's actually queryable at runtime — keep it in sync with Loom/Bridge/*.swift by hand.
//
// Each entry is "<path>|<insertion>|<display>" — a flat string, not a struct, because the pill
// bar only ever needs a label to show and a doc lookup: three fields let SuggestionEngine derive
// both without a model type, and the pipe delimiter is chosen precisely because none of the three
// fields ever contain one (union-type "|" only ever shows up inside `display`, split with
// maxSplits so it's preserved verbatim there).
//   path      — dotted method/property path with no "Loom." prefix, e.g. "network.fetch",
//               "db.table.insert", "device.batteryLevel". Chained calls collapse the
//               intermediate parens (db.table(name).insert → path "db.table.insert") so the
//               namespace (path's first dot-separated segment) is always a clean lookup key.
//   insertion — exact text a pill tap inserts. Empty call parens "()" mark where the caret
//               should land (SuggestionEngine.insert finds the first "()" pair); a path with no
//               parens at all (device.*) is a property read, caret goes to the end instead.
//   display   — "path(typed args): return — one-line summary", shown in the long-form list and
//               (prefixed with "Loom." where appropriate) fed to the AI system prompt.
enum LoomAPICatalog {
    static let signatures: [String] = [
        // MARK: log (Loom.log.*, derived from LogLevel.allCases — see LogBridge.swift:20-26)
        "log.debug|Loom.log.debug()|log.debug(message: any, data?: object): void — synchronous debug-level log entry",
        "log.info|Loom.log.info()|log.info(message: any, data?: object): void — synchronous info-level log entry",
        "log.warn|Loom.log.warn()|log.warn(message: any, data?: object): void — synchronous warn-level log entry",
        "log.error|Loom.log.error()|log.error(message: any, data?: object): void — synchronous error-level log entry",

        // MARK: console (global, not under Loom — aliases onto Loom.log)
        "console.log|console.log()|console.log(value: any): void — alias for Loom.log.debug",
        "console.info|console.info()|console.info(value: any): void — alias for Loom.log.info",
        "console.warn|console.warn()|console.warn(value: any): void — alias for Loom.log.warn",
        "console.error|console.error()|console.error(value: any): void — alias for Loom.log.error",

        // MARK: network
        "network.fetch|await Loom.network.fetch()|network.fetch(url: string, options?: {method?, headers?, body?}): Promise<Response> — HTTP fetch; read via response._body, no .text()/.json()",
        "network.fetchAll|await Loom.network.fetchAll()|network.fetchAll(requests: {url, method?, headers?, body?}[]): Promise<Response[]> — runs up to 64 requests concurrently (8 in flight) and resolves positionally; a failed element has status 0 and an error string rather than rejecting the batch. The only way to overlap network calls — plain fetch() blocks the script thread, so Promise.all over it stays serial",

        // MARK: files (project-sandboxed, no absolute paths or ../ traversal)
        "files.read|await Loom.files.read()|files.read(path: string): Promise<string> — read a project-relative file as UTF-8",
        "files.write|await Loom.files.write()|files.write(path: string, content: string): Promise<void> — atomic UTF-8 write, creates parent dirs",
        "files.list|await Loom.files.list()|files.list(dir?: string): Promise<string[]> — filenames in dir, non-recursive",
        "files.pick|await Loom.files.pick()|files.pick(): Promise<{name, content} | undefined> — system document picker, text files only",

        // MARK: db (auto-migrating SQLite; db.table(name) mirrors db.shared.table(name))
        "db.table|Loom.db.table()|db.table(name: string): TableProxy — project-private table reference, schema inferred on first insert",
        "db.table.insert|await Loom.db.table().insert()|db.table(name).insert(row: object): Promise<void> — insert a row, adding columns as needed",
        "db.table.select|await Loom.db.table().select()|db.table(name).select(where?: object): Promise<object[]> — select rows matching equality conditions",
        "db.table.update|await Loom.db.table().update()|db.table(name).update(where: object, values: object): Promise<number> — update matching rows, returns count",
        "db.table.delete|await Loom.db.table().delete()|db.table(name).delete(where: object): Promise<number> — delete matching rows, returns count",
        "db.shared.table|Loom.db.shared.table()|db.shared.table(name: string): TableProxy — same insert/select/update/delete, shared across all projects",

        // MARK: kv (NSUbiquitousKeyValueStore, iCloud-synced, all synchronous)
        "kv.get|Loom.kv.get()|kv.get(key: string): any | undefined — synchronous read, no Promise",
        "kv.set|Loom.kv.set()|kv.set(key: string, value: any): void — synchronous write",
        "kv.delete|Loom.kv.delete()|kv.delete(key: string): void — synchronous delete, no error if missing",
        "kv.list|Loom.kv.list()|kv.list(): string[] — all keys for this project",

        // MARK: ui (blocks the script until the user dismisses)
        "ui.alert|await Loom.ui.alert()|ui.alert(options?: {title?, message?}): Promise<void> — OK-only alert",
        "ui.input|await Loom.ui.input()|ui.input(options?: {prompt?, placeholder?}): Promise<string> — text prompt, cancel returns empty string",
        "ui.table|await Loom.ui.table()|ui.table(options?: {rows?, columns?}): Promise<void> — read-only scrollable table sheet",
        "ui.web|await Loom.ui.web()|ui.web(options: {template?: string, html?: string, title?: string, subtitle?: string, button?: string | false, bar?: boolean, routes: Record<string, (req) => string>}): Promise<void> — htmx web sheet; serves an .html page and routes its hx-* requests to your functions. Blocks until dismissed. button renames the Done button or removes it (false); bar: false hides the nav bar entirely. routes must be passed here, never in loom() config",

        // MARK: notify
        "notify.schedule|await Loom.notify.schedule()|notify.schedule(options?: {title?, body?, trigger?}): Promise<string> — one-shot local notification, returns id",

        // MARK: device (property bag, no methods — UIDevice snapshot)
        "device.batteryLevel|Loom.device.batteryLevel|device.batteryLevel: number | null — 0.0–1.0, null when unknown",
        "device.isCharging|Loom.device.isCharging|device.isCharging: boolean — true if charging or full",
        "device.model|Loom.device.model|device.model: string — device model name, e.g. iPhone",
        "device.systemVersion|Loom.device.systemVersion|device.systemVersion: string — iOS version string",

        // MARK: clipboard (synchronous)
        "clipboard.read|Loom.clipboard.read()|clipboard.read(): string — pasteboard text, empty string if none",
        "clipboard.write|Loom.clipboard.write()|clipboard.write(text: string): void — write text to pasteboard",

        // MARK: location
        "location.current|await Loom.location.current()|location.current(): Promise<{lat, lng, accuracy}> — one-shot fix, requests when-in-use authorization",

        // MARK: speech
        "speech.speak|await Loom.speech.speak()|speech.speak(text: string): Promise<void> — text-to-speech, resolves when finished",
        "speech.recognize|await Loom.speech.recognize()|speech.recognize(): Promise<string> — mic transcription, stops when user taps Done",

        // MARK: contacts (CNContactStore)
        "contacts.search|await Loom.contacts.search()|contacts.search(query?: string): Promise<Contact[]> — search by name; omit query for all contacts",
        "contacts.create|await Loom.contacts.create()|contacts.create(fields: object): Promise<{id}> — create a contact",
        "contacts.update|await Loom.contacts.update()|contacts.update(id: string, fields: object): Promise<void> — partial update",
        "contacts.delete|await Loom.contacts.delete()|contacts.delete(id: string): Promise<void> — delete a contact",

        // MARK: calendar (EKEventStore)
        "calendar.events.list|await Loom.calendar.events.list()|calendar.events.list(opts?: {from?, to?}): Promise<Event[]> — list events across all calendars",
        "calendar.events.create|await Loom.calendar.events.create()|calendar.events.create(opts: {title?, start?, end?, notes?}): Promise<{id}> — create event on the default calendar",
        "calendar.events.update|await Loom.calendar.events.update()|calendar.events.update(id: string, opts: object): Promise<void> — partial update of event fields",
        "calendar.events.delete|await Loom.calendar.events.delete()|calendar.events.delete(id: string): Promise<void> — delete a single event occurrence",
        "calendar.reminders.create|await Loom.calendar.reminders.create()|calendar.reminders.create(opts: {title?, dueDate?}): Promise<{id}> — create a reminder",

        // MARK: photos (PHPhotoLibrary — files land in the project folder)
        "photos.pick|await Loom.photos.pick()|photos.pick(): Promise<string | null> — pick one photo, saved into the project folder as jpg",
        "photos.save|await Loom.photos.save()|photos.save(path: string): Promise<void> — save a project image into the photo library",

        // MARK: camera (AVFoundation + Vision)
        "camera.capture|await Loom.camera.capture()|camera.capture(): Promise<string | null> — take a photo, saved into the project folder as jpg",
        "camera.ocr|await Loom.camera.ocr()|camera.ocr(path: string): Promise<string> — Vision text recognition on a project image",
        "camera.barcode|await Loom.camera.barcode()|camera.barcode(path: string): Promise<string> — Vision barcode detection, first match",

        // MARK: health (HKHealthStore — type is a free-form HealthKit identifier string)
        "health.read|await Loom.health.read()|health.read(type: string, opts?: {from?, to?, limit?, unit?}): Promise<Sample[]> — read any HealthKit sample type by name",
        "health.stats|await Loom.health.stats()|health.stats(type: string, opts?: {from?, to?, op?, bucket?, unit?}): Promise<Stats> — source-de-duplicated aggregate",
        "health.profile|await Loom.health.profile()|health.profile(): Promise<{biologicalSex?, bloodType?, dateOfBirth?, ...}> — the fixed HealthKit characteristics",
        "health.saveWorkout|await Loom.health.saveWorkout()|health.saveWorkout(opts: {type, duration?, start?, end?, distance?}): Promise<void> — write a workout sample",

        // MARK: ai (Loom.ai — script-facing bridge; separate from the in-app authoring assistant)
        "ai.complete|await Loom.ai.complete()|ai.complete(prompt: string, opts?: {provider?, maxTokens?, instructions?, model?}): Promise<string> — single-turn completion",
        "ai.completeAll|await Loom.ai.completeAll()|ai.completeAll(prompts: string[], opts?: object): Promise<{text, error}[]> — runs up to 64 completions concurrently (8 in flight), same opts as complete(), resolving positionally; a failed prompt carries its error instead of rejecting the batch",
        "ai.chat|await Loom.ai.chat()|ai.chat(messages: {role, content}[], opts?: object): Promise<string> — multi-turn chat (single-turn on the apple provider)",
        "ai.search|await Loom.ai.search()|ai.search(query: string, opts: {corpus: string[]}): Promise<{text, score}[]> — on-device semantic search over a provided corpus",

        // MARK: activity (Live Activities — layouts are w.* trees, same as widgets)
        "activity.start|await Loom.activity.start()|activity.start(options: {key, content?, compactLeading?, compactTrailing?, minimal?, expanded?, staleAfter?, relevance?, style?}): Promise<string | null> — starts a Live Activity, resolves the key (null if iOS declined)",
        "activity.update|await Loom.activity.update()|activity.update(key: string, options?: {content?, compactLeading?, compactTrailing?, minimal?, expanded?, staleAfter?, relevance?, alert?}): Promise<boolean> — replaces the layout, false if no activity has that key",
        "activity.end|await Loom.activity.end()|activity.end(key: string, options?: {content?, dismiss?: 'immediate' | 'default' | number}): Promise<boolean> — ends it, false if no activity has that key",
        "activity.list|await Loom.activity.list()|activity.list(): Promise<{key, state}[]> — this project's running activities",

        // MARK: share (Share Extension input, synchronous re-read of ctx.input)
        "share.input|Loom.share.input()|share.input(): {type, value} | undefined — the shared item for a share-triggered run",

        // MARK: w (widget.ts only — import { w } from '@loom/widget', not under Loom)
        "w.vstack|w.vstack()|w.vstack(children?, props?): ComponentNode — vertical stack",
        "w.hstack|w.hstack()|w.hstack(children?, props?): ComponentNode — horizontal stack",
        "w.zstack|w.zstack()|w.zstack(children?, props?): ComponentNode — layered (depth) stack",
        "w.spacer|w.spacer()|w.spacer(props?: {minLength?}): ComponentNode — flexible or fixed empty space",
        "w.divider|w.divider()|w.divider(props?: {color?}): ComponentNode — thin dividing line",
        "w.text|w.text()|w.text(content?, props?: {font?, bold?, italic?, alignment?, color?, lineLimit?}): ComponentNode — text label",
        "w.date|w.date()|w.date(isoString?, props?: {style?: 'relative'|'days'|'date'|'time'|'timer'|'offset', font?, bold?, alignment?, color?, lineLimit?}): ComponentNode — live date text, re-renders itself without a run. 'relative' always shows two units ('4 days, 11 hrs'); use 'days' for a plain whole-day countdown ('4 days', 'Tomorrow') that changes at midnight",
        "w.label|w.label()|w.label(props: {icon, title, subtitle?, color?}): ComponentNode — SF Symbol + title/subtitle row",
        "w.image|w.image()|w.image(url?, props?: {cornerRadius?, width?, height?}): ComponentNode — remote image, scaled to fill",
        "w.icon|w.icon()|w.icon(name?, props?: {size?, color?}): ComponentNode — a single SF Symbol",
        "w.link|w.link()|w.link(props: {label, url, font?, color?}): ComponentNode — tappable link text",
        "w.ring|w.ring()|w.ring(props?: {value?, total?, color?, label?, caption?}): ComponentNode — donut-style progress ring",
        "w.gauge|w.gauge()|w.gauge(props?: {value?, min?, max?, color?, label?}): ComponentNode — horizontal bar-fill gauge",
        "w.lineChart|w.lineChart()|w.lineChart(props: {data, color?, smooth?}): ComponentNode — Swift Charts line",
        "w.barChart|w.barChart()|w.barChart(props: {data, color?}): ComponentNode — Swift Charts bar",
        "w.sparkline|w.sparkline()|w.sparkline(props: {data, color?}): ComponentNode — minimal line, axes hidden",
        "w.progressBar|w.progressBar()|w.progressBar(props?: {value?, total?, color?, label?}): ComponentNode — bar fill with optional caption",
        "w.rectangle|w.rectangle()|w.rectangle(children?, props?: {color?, cornerRadius?, padding?}): ComponentNode — filled rounded rectangle",
        "w.capsule|w.capsule()|w.capsule(children?, props?: {color?, padding?}): ComponentNode — filled capsule shape",
        "w.circle|w.circle()|w.circle(children?, props?: {color?, size?}): ComponentNode — filled circle shape",
        "w.gradient|w.gradient()|w.gradient(props: {colors: string[], direction?}): ComponentNode — gradient value for a background prop",
        "w.button|w.button()|w.button(props: {label, kvKey, color?, font?}): ComponentNode — tappable pill, writes kvKey on tap",
        "w.toggle|w.toggle()|w.toggle(props: {label, kvKey, value, color?, font?}): ComponentNode — switch, writes kvKey on change",
    ]

    /// The 19 real `Loom.*` roots (excludes `console` and `w`, which aren't under the Loom
    /// global) — derived from `signatures` rather than a second literal list, so adding a
    /// namespace above can't silently drift out of sync with the idle-bar pill list.
    static let namespaces: [String] = {
        let roots = Set(signatures.map { path(for: $0).split(separator: ".")[0] }.map(String.init))
        return roots.subtracting(["console", "w"]).sorted()
    }()

    /// One system-prompt line per entry, "Loom." prefixed except for `console`/`w` which aren't
    /// under the Loom global. Appended to the assistant's system prompt (AssistantSession.swift)
    /// so it has real signatures instead of only doc page titles.
    static let promptManifest: String = signatures.map { line in
        let p = path(for: line)
        let d = display(for: line)
        return (p.hasPrefix("console.") || p.hasPrefix("w.")) ? d : "Loom." + d
    }.joined(separator: "\n")

    private static let byLabel: [String: String] = Dictionary(
        uniqueKeysWithValues: signatures.map { (label(for: $0), $0) }
    )

    /// Catalog labels whose path starts with (or, failing that, contains) `token` — the text
    /// typed after "Loom.". Case-insensitive, sorted for a stable pill order.
    static func matches(_ token: String) -> [String] {
        guard !token.isEmpty else { return [] }
        let t = token.lowercased()
        let prefixHits = signatures.filter { path(for: $0).lowercased().hasPrefix(t) }
        let pool = prefixHits.isEmpty ? signatures.filter { path(for: $0).lowercased().contains(t) } : prefixHits
        return pool.map(label(for:)).sorted()
    }

    // MARK: - htmx (page templates for Loom.ui.web)

    /// Deliberately NOT in `signatures`: these are markup attributes, not Loom.* JS methods, and
    /// `signatures` feeds `promptManifest` for every TypeScript file plus a per-entry doc-page
    /// assertion neither of which applies here. Only surfaced when the open file is `.html`.
    static let htmxAttributes: [String] = [
        "hx-get", "hx-post", "hx-put", "hx-patch", "hx-delete",
        "hx-target", "hx-swap", "hx-trigger", "hx-vals", "hx-include",
        "hx-indicator", "hx-confirm", "hx-select", "hx-push-url",
        "hx-disable", "hx-boost", "hx-on",
    ]

    /// Prefix hits first, falling back to substring hits — mirrors `matches(_:)`. An empty token
    /// returns the whole list so the idle bar is useful before anything is typed.
    static func htmxMatches(_ token: String) -> [String] {
        guard !token.isEmpty else { return htmxAttributes }
        let t = token.lowercased()
        let prefixHits = htmxAttributes.filter { $0.hasPrefix(t) }
        return prefixHits.isEmpty ? htmxAttributes.filter { $0.contains(t) } : prefixHits
    }

    static func label(for line: String) -> String {
        let p = path(for: line)
        return (p.hasPrefix("console.") || p.hasPrefix("w.")) ? p : "Loom." + p
    }

    /// nil for a label that isn't a catalog entry (an AI-sourced pill) — the caller falls back
    /// to inserting the pill's own text verbatim.
    static func insertion(for label: String) -> String? {
        guard let line = byLabel[label] else { return nil }
        return fields(line).insertion
    }

    static func docPage(for label: String) -> DocPage? {
        // htmx pills carry no catalog line — long-press should still reach the guide.
        if label.hasPrefix("hx-") { return DocCatalog.page(forFilename: "web-sheets.md") }
        guard let line = byLabel[label] else { return nil }
        let ns = String(path(for: line).split(separator: ".")[0])
        let filename: String
        switch ns {
        case "console": filename = "log.md"
        case "w": filename = "widget-builder.md"
        default: filename = ns + ".md"
        }
        return DocCatalog.page(forFilename: filename)
    }

    // MARK: - Field parsing ("path|insertion|display", pipe-delimited, display kept verbatim)

    private static func fields(_ line: String) -> (path: String, insertion: String, display: String) {
        let parts = line.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3 else { return ("", "", line) }
        return (String(parts[0]), String(parts[1]), String(parts[2]))
    }

    // No private `insertion(for:)` helper here deliberately — it previously shadowed the public
    // `insertion(for label:)` above with an identical signature (differing only by return type),
    // so the public function's internal call silently recursed into itself instead of reaching
    // this file's field accessor, making every lookup return nil. Caught by the self-check below.
    // Not private: ExampleCatalog.runPlaygroundCoverageCheck() greps the playground sources for
    // these paths, and re-deriving them by stripping "Loom." off `label(for:)` would be the same
    // string twice.
    static func path(for line: String) -> String { fields(line).path }
    private static func display(for line: String) -> String { fields(line).display }

    // No test target exists in this project (see ModuleBundler.runSelfCheck) — callable directly
    // from LoomApp.init() in DEBUG instead of XCTest.
    #if DEBUG
    @discardableResult
    static func runSelfCheck() -> Bool {
        var failures: [String] = []
        func check(_ name: String, _ condition: @autoclosure () -> Bool) {
            if !condition() { failures.append(name) }
        }

        check("namespaces == the 19 real Loom.* roots", namespaces.count == 19)
        for line in signatures {
            let f = fields(line)
            check("\(line): 3 non-empty fields", !f.path.isEmpty && !f.insertion.isEmpty && !f.display.isEmpty)
            check("\(line): path has no space or pipe", !f.path.contains(" ") && !f.path.contains("|"))
            check("\(line): resolves a doc page", docPage(for: label(for: line)) != nil)
        }
        check("matches(network) finds fetch", matches("network").contains("Loom.network.fetch"))
        check("kv.get insertion is sync (no await)", insertion(for: "Loom.kv.get") == "Loom.kv.get()")
        check("network.fetch insertion awaits", insertion(for: "Loom.network.fetch") == "await Loom.network.fetch()")
        check("unknown label has no insertion", insertion(for: "not.a.real.entry") == nil)

        check("htmxAttributes non-empty", !htmxAttributes.isEmpty)
        check("every htmx entry is an hx- attribute", htmxAttributes.allSatisfy { $0.hasPrefix("hx-") })
        check("htmxMatches(hx-t) finds hx-target", htmxMatches("hx-t").contains("hx-target"))
        check("htmxMatches(empty) is the whole list", htmxMatches("").count == htmxAttributes.count)
        check("htmx pills resolve the web-sheets guide", docPage(for: "hx-get") != nil)

        if failures.isEmpty {
            print("[LoomAPICatalog] self-check passed")
        } else {
            print("[LoomAPICatalog] self-check FAILED: \(failures.joined(separator: ", "))")
        }
        return failures.isEmpty
    }
    #endif
}
