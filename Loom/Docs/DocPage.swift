import Foundation

enum DocCategory: String, CaseIterable, Identifiable {
    case gettingStarted = "Getting Started"
    case guides = "Guides & Tutorials"
    case apiReference = "API Reference"
    case examples = "Examples"
    case troubleshooting = "Troubleshooting"

    var id: String { rawValue }

    // Source-tree organization only. The app bundle flattens all resources to its
    // root (confirmed by how Resources/Vendors/*.js actually land — see VendorRegistry),
    // so DocDetailView looks files up by filename alone, not by this folder.
    var folderName: String {
        switch self {
        case .gettingStarted: return "getting-started"
        case .guides: return "guides"
        case .apiReference: return "api-reference"
        case .examples: return "examples"
        case .troubleshooting: return "troubleshooting"
        }
    }
}

struct DocPage: Identifiable, Hashable {
    let category: DocCategory
    let filename: String
    let title: String

    var id: String { filename }

    // Internal cross-links in doc content use loom-doc://<category-folder>/<filename>;
    // DocsView resolves these back to a DocPage by filename alone (see DocCatalog.page(forFilename:)).
    var linkURL: URL { URL(string: "loom-doc://\(category.folderName)/\(filename)")! }
}

enum DocCatalog {
    // Example write-ups are doc pages too. One line, and every example becomes searchable in
    // DocsView *and* readable by the authoring assistant through read_doc — which could previously
    // see all 43 doc pages and none of the shipped sample projects.
    static let pages: [DocPage] = writtenPages + ExampleCatalog.all.map {
        DocPage(category: .examples, filename: $0.docFilename, title: $0.title)
    }

    private static let writtenPages: [DocPage] = [
        DocPage(category: .gettingStarted, filename: "welcome.md", title: "Welcome to Loom"),
        DocPage(category: .gettingStarted, filename: "getting-started.md", title: "Getting Started"),
        DocPage(category: .gettingStarted, filename: "core-concepts.md", title: "Core Concepts"),

        DocPage(category: .guides, filename: "first-script.md", title: "Your First Script"),
        DocPage(category: .guides, filename: "database.md", title: "Working with the Database"),
        DocPage(category: .guides, filename: "widgets.md", title: "Building a Widget"),
        DocPage(category: .guides, filename: "web-sheets.md", title: "htmx Web Sheets"),
        DocPage(category: .guides, filename: "siri-shortcuts.md", title: "Siri, Shortcuts & URL Scheme"),
        DocPage(category: .guides, filename: "background-tasks.md", title: "Background Tasks"),
        DocPage(category: .guides, filename: "working-with-ai.md", title: "Working with AI"),
        DocPage(category: .guides, filename: "ai-assistant.md", title: "The AI Authoring Assistant"),
        DocPage(category: .guides, filename: "editor-suggestions.md", title: "Editor Suggestions"),
        DocPage(category: .guides, filename: "permissions-privacy.md", title: "Permissions & Privacy"),
        DocPage(category: .guides, filename: "share-extension.md", title: "Sharing Into Loom"),
        DocPage(category: .guides, filename: "debugging.md", title: "Debugging & the Console"),
        DocPage(category: .guides, filename: "exporting-projects.md", title: "Exporting & Importing Projects"),
        DocPage(category: .guides, filename: "entities-spotlight.md", title: "Entities & Spotlight"),
        DocPage(category: .guides, filename: "modules.md", title: "Splitting a Script Across Files"),

        DocPage(category: .apiReference, filename: "overview.md", title: "Overview"),
        DocPage(category: .apiReference, filename: "loom-config.md", title: "loom() Config"),
        DocPage(category: .apiReference, filename: "context.md", title: "The ctx Object"),
        DocPage(category: .apiReference, filename: "network.md", title: "Loom.network"),
        DocPage(category: .apiReference, filename: "files.md", title: "Loom.files"),
        DocPage(category: .apiReference, filename: "db.md", title: "Loom.db"),
        DocPage(category: .apiReference, filename: "kv.md", title: "Loom.kv"),
        DocPage(category: .apiReference, filename: "log.md", title: "Loom.log"),
        DocPage(category: .apiReference, filename: "ui.md", title: "Loom.ui"),
        DocPage(category: .apiReference, filename: "notify.md", title: "Loom.notify"),
        DocPage(category: .apiReference, filename: "activity.md", title: "Loom.activity"),
        DocPage(category: .apiReference, filename: "health.md", title: "Loom.health"),
        DocPage(category: .apiReference, filename: "location.md", title: "Loom.location"),
        DocPage(category: .apiReference, filename: "contacts.md", title: "Loom.contacts"),
        DocPage(category: .apiReference, filename: "calendar.md", title: "Loom.calendar"),
        DocPage(category: .apiReference, filename: "camera.md", title: "Loom.camera"),
        DocPage(category: .apiReference, filename: "photos.md", title: "Loom.photos"),
        DocPage(category: .apiReference, filename: "share.md", title: "Loom.share"),
        DocPage(category: .apiReference, filename: "clipboard.md", title: "Loom.clipboard"),
        DocPage(category: .apiReference, filename: "speech.md", title: "Loom.speech"),
        DocPage(category: .apiReference, filename: "device.md", title: "Loom.device"),
        DocPage(category: .apiReference, filename: "ai.md", title: "Loom.ai"),
        DocPage(category: .apiReference, filename: "widget-builder.md", title: "Widget Builder (@loom/widget)"),
        DocPage(category: .apiReference, filename: "vendor-packages.md", title: "Vendor Packages"),

        DocPage(category: .troubleshooting, filename: "troubleshooting.md", title: "Troubleshooting"),
        DocPage(category: .troubleshooting, filename: "limitations.md", title: "Limitations"),
    ]

    static func page(forFilename filename: String) -> DocPage? {
        pages.first { $0.filename == filename }
    }
}
