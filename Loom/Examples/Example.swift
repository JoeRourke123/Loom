import Foundation

enum ExampleLevel: String, CaseIterable, Identifiable, Hashable {
    case starter = "Starter"
    case intermediate = "Intermediate"
    case advanced = "Advanced"
    /// Not an example of anything — a smoke test of the whole bridge surface.
    case playground = "Playground"

    var id: String { rawValue }

    var blurb: String {
        switch self {
        case .starter: return "One idea each, small enough to read in a sitting."
        case .intermediate: return "A few APIs working together — widgets, storage, background runs."
        case .advanced: return "Siri intents, Spotlight entities, web sheets and multi-file projects."
        case .playground: return "Calls every API once and reports what worked, what broke and what it skipped."
        }
    }

    var icon: String {
        switch self {
        case .starter: return "1.circle"
        case .intermediate: return "2.circle"
        case .advanced: return "3.circle"
        case .playground: return "testtube.2"
        }
    }
}

/// A runnable sample project shipped inside the app bundle.
///
/// Source files live at `<repo>/Examples/<slug>/` and are bundled by a **folder reference** on the
/// Loom target, not by the synchronized group that carries everything under `Loom/`. Two reasons:
/// Xcode classifies `.ts` as `sourcecode.typescript`, routes it to the Sources phase, and then
/// silently drops it because nothing compiles TypeScript; and a folder reference is copied verbatim,
/// so `Examples/<slug>/` survives into the bundle instead of being flattened to its root the way
/// `Loom/Resources/**` is (see DocPage.swift). Keeping the directory means files can just be called
/// `main.ts` — no per-example filename prefix to strip back off.
///
/// The write-up is the exception: it lives with the docs at `Loom/Resources/Docs/examples/<slug>.md`,
/// flattens like every other doc page, and is registered in `DocCatalog`.
struct Example: Identifiable, Hashable {
    let slug: String
    let title: String
    let tagline: String
    /// SF Symbol.
    let icon: String
    let level: ExampleLevel
    /// Bridge namespaces and features this demonstrates. Shown as chips, and searchable.
    let apis: [String]
    /// Destination filenames, written into the project folder in this order. `main.ts` first.
    let files: [String]

    var id: String { slug }

    /// The write-up. Registered in DocCatalog too, so it's searchable in Docs and readable by the
    /// authoring assistant via read_doc.
    var docFilename: String { "\(slug).md" }

    func bundleURL(for file: String) -> URL? {
        let name = file as NSString
        return Bundle.main.url(
            forResource: name.deletingPathExtension,
            withExtension: name.pathExtension,
            subdirectory: "Examples/\(slug)"
        )
    }

    func source(for file: String) -> String? {
        guard let url = bundleURL(for: file) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    var writeUp: String? {
        if let url = Bundle.main.url(forResource: slug, withExtension: "md") {
            return try? String(contentsOf: url, encoding: .utf8)
        }
        // Falls back to a README.md inside the example's own folder. The playground uses this:
        // it needs a write-up but is not a doc page, and registering a DEBUG-only page in
        // DocCatalog would put it in the user-facing Docs tab and its search index.
        guard let url = bundleURL(for: "README.md") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

enum ExampleCatalog {
    static let all: [Example] = [
        // MARK: Starter

        Example(
            slug: "clipboard-cleaner",
            title: "Clipboard Cleaner",
            tagline: "Strip tracking junk out of whatever you just copied.",
            icon: "wand.and.sparkles",
            level: .starter,
            apis: ["Loom.clipboard", "Loom.ui"],
            files: ["main.ts"]
        ),
        Example(
            slug: "on-this-day",
            title: "On This Day",
            tagline: "One HTTP request, one alert — and the response gotcha that catches everyone.",
            icon: "calendar.badge.clock",
            level: .starter,
            apis: ["Loom.network", "Loom.ui"],
            files: ["main.ts"]
        ),
        Example(
            slug: "battery-ring",
            title: "Battery Ring",
            tagline: "Your first widget, with no network and no permissions.",
            icon: "battery.75percent",
            level: .starter,
            apis: ["Loom.device", "Widgets"],
            files: ["main.ts"]
        ),
        Example(
            slug: "speak-it",
            title: "Speak It",
            tagline: "Reads text aloud from the share sheet, the clipboard, or a prompt.",
            icon: "speaker.wave.2.fill",
            level: .starter,
            apis: ["Loom.share", "Loom.speech", "Loom.clipboard", "ctx.trigger"],
            files: ["main.ts"]
        ),
        Example(
            slug: "quick-note",
            title: "Quick Note",
            tagline: "Jot or dictate a line into a notes file. Works from Siri.",
            icon: "square.and.pencil",
            level: .starter,
            apis: ["Loom.files", "Loom.speech", "Loom.log", "Siri intents"],
            files: ["main.ts"]
        ),

        // MARK: Intermediate

        Example(
            slug: "weather-brief",
            title: "Weather Brief",
            tagline: "Local forecast on your home screen, cached and refreshed in the background.",
            icon: "cloud.sun.fill",
            level: .intermediate,
            apis: ["Loom.location", "Loom.network", "Loom.kv", "Widgets", "Background"],
            files: ["main.ts"]
        ),
        Example(
            slug: "hn-digest",
            title: "Hacker News Digest",
            tagline: "Top stories, with a notification when something big lands.",
            icon: "newspaper.fill",
            level: .intermediate,
            apis: ["Loom.network", "Loom.ui", "Loom.notify", "Loom.kv", "Background"],
            files: ["main.ts"]
        ),
        Example(
            slug: "habit-rings",
            title: "Habit Rings",
            tagline: "Tap the widget itself to log a habit — no need to open the app.",
            icon: "checkmark.circle.fill",
            level: .intermediate,
            apis: ["Loom.kv", "Widgets", "Interactive widgets"],
            files: ["main.ts"]
        ),
        Example(
            slug: "step-trends",
            title: "Step Trends",
            tagline: "A week of steps against your own average, straight from HealthKit.",
            icon: "figure.walk",
            level: .intermediate,
            apis: ["Loom.health", "Widgets"],
            files: ["main.ts"]
        ),
        Example(
            slug: "focus-timer",
            title: "Focus Timer",
            tagline: "A session that counts itself down on your Lock Screen, and stops when you tap it.",
            icon: "brain.head.profile",
            level: .intermediate,
            apis: ["Loom.activity", "Loom.kv", "Loom.notify", "Live Activities", "Background"],
            files: ["main.ts"]
        ),
        Example(
            slug: "csv-inspector",
            title: "CSV Inspector",
            tagline: "Pick any CSV and get a typed column summary back.",
            icon: "tablecells",
            level: .intermediate,
            apis: ["Loom.files", "Loom.db", "Loom.ui", "csv-parse", "lodash", "mathjs"],
            files: ["main.ts"]
        ),

        // MARK: Advanced

        Example(
            slug: "reading-list",
            title: "Reading List",
            tagline: "Share articles in, browse them in a web sheet, search them two ways.",
            icon: "books.vertical.fill",
            level: .advanced,
            apis: ["Loom.share", "Loom.db", "Loom.ui.web", "Loom.ai", "cheerio", "Remote modules"],
            files: ["main.ts", "views.ts", "index.html"]
        ),
        Example(
            slug: "expense-log",
            title: "Expense Log",
            tagline: "\"Hey Siri, log twelve pounds for lunch.\" Indexed into Spotlight.",
            icon: "sterlingsign.circle.fill",
            level: .advanced,
            apis: ["Siri intents", "Entities", "Loom.db.shared", "Widgets"],
            files: ["main.ts", "money.ts"]
        ),
        Example(
            slug: "receipt-scanner",
            title: "Receipt Scanner",
            tagline: "Photograph a receipt, let on-device AI read it, file it with your expenses.",
            icon: "doc.text.viewfinder",
            level: .advanced,
            apis: ["Loom.camera", "Loom.photos", "Loom.ai", "Loom.db.shared", "Loom.ui"],
            files: ["main.ts"]
        ),
        Example(
            slug: "pantry",
            title: "Pantry",
            tagline: "Scan a barcode, track what's in the cupboard, get told before it expires.",
            icon: "barcode.viewfinder",
            level: .advanced,
            apis: ["Loom.camera", "Loom.network", "Loom.db", "Loom.notify", "Loom.ui.web", "Entities", "Background", "date-fns"],
            files: ["main.ts", "index.html"]
        ),
        Example(
            slug: "meeting-prep",
            title: "Meeting Prep",
            tagline: "Reads your day, looks up who you're meeting, and briefs you before it starts.",
            icon: "calendar.badge.checkmark",
            level: .advanced,
            apis: ["Loom.calendar", "Loom.contacts", "Loom.ai", "Loom.notify", "Widgets", "Background"],
            files: ["main.ts"]
        ),

        // MARK: Playground

        // Not an example of anything — it calls every entry in LoomAPICatalog.signatures once and
        // prints a pass/fail table. Kept in this catalog rather than off to one side so it
        // inherits the bundling, the scaffolder, and above all runCompilerSelfCheck(), which puts
        // all 21 files through the real compiler at launch.
        //
        // Coverage is enforced by runPlaygroundCoverageCheck(): every catalog path must appear
        // verbatim in one of these files, which it does because the probe label *is* the path.
        Example(
            slug: "playground",
            title: "API Playground",
            tagline: "Every API, called once, with a pass/fail table.",
            icon: "testtube.2",
            level: .playground,
            apis: ["Every namespace", "Widgets", "Siri intents", "Entities", "Vendor packages"],
            files: [
                "main.ts", "probe.ts",
                "activity.ts", "ai.ts", "calendar.ts", "camera.ts", "clipboard.ts", "contacts.ts",
                "db.ts", "device.ts", "files.ts", "health.ts", "kv.ts", "location.ts", "log.ts",
                "network.ts", "notify.ts", "photos.ts", "share.ts", "speech.ts", "ui.ts",
                "vendors.ts",
            ]
        ),
    ]

    static func examples(at level: ExampleLevel) -> [Example] {
        all.filter { $0.level == level }
    }

    static func example(forDocFilename filename: String) -> Example? {
        all.first { $0.docFilename == filename }
    }
}
