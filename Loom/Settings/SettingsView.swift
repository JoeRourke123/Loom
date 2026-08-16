import SwiftUI

struct SettingsView: View {
    @AppStorage("editorLineWrapping") private var lineWrapping = true
    @AppStorage("editorSuggestions") private var suggestionsEnabled = false
    // Default on — matches ModuleBundler.remoteModulesEnabled, which reads the same key.
    @AppStorage("remoteModulesEnabled") private var remoteModules = true
    private var providerStore = AIProviderStore.shared

    var body: some View {
        Form {
            Section {
                Toggle("Line Wrapping", isOn: $lineWrapping)
                Toggle("Code Suggestions", isOn: $suggestionsEnabled)
                if suggestionsEnabled {
                    if providerStore.providers.isEmpty {
                        NavigationLink("Add a Provider…") { AIProviderListView() }
                    } else {
                        Picker("Completions Model", selection: Binding(
                            get: { providerStore.completionsID },
                            set: { providerStore.completionsID = $0 }
                        )) {
                            Text("Off").tag(Optional<UUID>.none)
                            ForEach(providerStore.providers) { provider in
                                Text(provider.name).tag(Optional(provider.id))
                            }
                        }
                    }
                }
            } header: {
                Text("Editor")
            } footer: {
                Text("Suggestions add a pill bar above the keyboard and inline completions while typing. Off by default — enabling it sends the current file to the completions model on a pause in typing.")
            }
            Section {
                if providerStore.providers.isEmpty {
                    NavigationLink("Add a Provider…") { AIProviderListView() }
                } else {
                    Picker("Assistant Model", selection: Binding(
                        get: { providerStore.selectedID ?? providerStore.providers.first?.id },
                        set: { providerStore.selectedID = $0 }
                    )) {
                        ForEach(providerStore.providers) { provider in
                            Text(provider.name).tag(Optional(provider.id))
                        }
                    }
                    NavigationLink("Manage Providers…") { AIProviderListView() }
                }
            } header: {
                Text("AI Providers")
            } footer: {
                Text("Bring your own key — any Anthropic- or OpenAI-compatible endpoint. One list serves the authoring assistant, code suggestions, and scripts: `Loom.ai.complete(p, { provider: 'Claude' })` matches a provider by name, and `'apple'` runs the on-device model.")
            }
            Section {
                Toggle("Remote Modules", isOn: $remoteModules)
                NavigationLink("Cached Modules…") { RemoteModuleCacheView() }
            } header: {
                Text("Modules")
            } footer: {
                Text("Scripts can import a URL directly: `import confetti from 'https://esm.sh/canvas-confetti?bundle'`. Each URL is downloaded once, per project, then never re-fetched — so a script keeps running offline and can't change behaviour underneath you. Clear a cached module to pick up a new version.")
            }
        }
        .navigationTitle("Settings")
    }
}

// A cache manager, deliberately not a package browser — no search, no catalog, no install
// buttons. Nothing here downloads anything; entries appear only once a script has imported a URL.
private struct RemoteModuleCacheView: View {
    @State private var entries: [RemoteModuleCache.Entry] = []

    var body: some View {
        List {
            if entries.isEmpty {
                ContentUnavailableView(
                    "No Cached Modules",
                    systemImage: "shippingbox",
                    description: Text("Modules appear here after a script imports them by URL.")
                )
            } else {
                ForEach(Dictionary(grouping: entries, by: \.projectName).sorted(by: { $0.key < $1.key }), id: \.key) { projectName, items in
                    Section(projectName) {
                        ForEach(items) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.source).font(.callout)
                                Text(entry.byteCount.formatted(.byteCount(style: .file)))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .swipeActions {
                                Button("Delete", role: .destructive) {
                                    RemoteModuleCache.delete(entry)
                                    reload()
                                }
                            }
                        }
                    }
                }
                Section {
                    Button("Clear All", role: .destructive) {
                        RemoteModuleCache.clearAll()
                        reload()
                    }
                }
            }
        }
        .navigationTitle("Cached Modules")
        .onAppear(perform: reload)
    }

    private func reload() { entries = RemoteModuleCache.allEntries() }
}
