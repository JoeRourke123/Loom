import SwiftUI

// Provider CRUD only — which provider is *active* is chosen by the Picker in SettingsView.
struct AIProviderListView: View {
    private var store = AIProviderStore.shared
    @State private var editingProvider: AIProvider?
    @State private var isAddingNew = false

    var body: some View {
        List {
            ForEach(store.providers) { provider in
                Button {
                    editingProvider = provider
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(provider.name)
                            .foregroundStyle(.primary)
                        Text("\(provider.wire.displayName) · \(provider.model)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .onDelete { indexSet in
                indexSet.map { store.providers[$0] }.forEach(store.remove)
            }
        }
        .navigationTitle("Providers")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { isAddingNew = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $editingProvider) { provider in
            AIProviderEditView(provider: provider)
        }
        .sheet(isPresented: $isAddingNew) {
            AIProviderEditView(provider: nil)
        }
        .overlay {
            if store.providers.isEmpty {
                ContentUnavailableView(
                    "No Providers",
                    systemImage: "sparkles",
                    description: Text("Add an Anthropic- or OpenAI-compatible provider to use the authoring assistant.")
                )
            }
        }
    }
}

private struct AIProviderEditView: View {
    @Environment(\.dismiss) private var dismiss
    private let store = AIProviderStore.shared
    private let existingID: UUID?

    @State private var name: String
    @State private var wire: AIProvider.Wire
    @State private var baseURL: String
    @State private var model: String
    @State private var maxTokens: Int
    @State private var apiKey: String
    @State private var testState: TestState = .idle

    private enum TestState: Equatable {
        case idle, testing, success, failure(String)
    }

    // OpenAI's base URL must already include /v1 — AIClient just appends "chat/completions".
    // Anthropic's must NOT include a version path — AIClient appends "v1/messages" itself.
    // Getting this wrong produces a 404 on every request, regardless of model name.
    private static let defaultBaseURL: [AIProvider.Wire: String] = [
        .anthropic: "https://api.anthropic.com",
        .openai: "https://api.openai.com/v1",
    ]

    init(provider: AIProvider?) {
        existingID = provider?.id
        _name = State(initialValue: provider?.name ?? "")
        let initialWire = provider?.wire ?? .anthropic
        _wire = State(initialValue: initialWire)
        _baseURL = State(initialValue: provider?.baseURL ?? Self.defaultBaseURL[initialWire]!)
        _model = State(initialValue: provider?.model ?? "")
        _maxTokens = State(initialValue: provider?.maxTokens ?? 8192)
        _apiKey = State(initialValue: provider.flatMap { AIProviderStore.shared.apiKey(for: $0) } ?? "")
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isValid: Bool { !trimmedName.isEmpty && !baseURL.isEmpty && !model.isEmpty && !apiKey.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    Picker("Wire Format", selection: $wire) {
                        ForEach(AIProvider.Wire.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .onChange(of: wire) { oldWire, newWire in
                        // Only auto-swap if the field still holds the old default — never
                        // clobber a URL the user actually typed (e.g. an OpenRouter/Ollama URL).
                        if baseURL == Self.defaultBaseURL[oldWire] {
                            baseURL = Self.defaultBaseURL[newWire] ?? baseURL
                        }
                    }
                    TextField("Base URL", text: $baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("Model", text: $model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Stepper("Max Tokens: \(maxTokens)", value: $maxTokens, in: 256...200_000, step: 256)
                } header: {
                    Text("Provider")
                } footer: {
                    Text("For OpenAI-wire endpoints, Base URL must include the version path (e.g. \u{201c}…/v1\u{201d}, or \u{201c}…/api/v1\u{201d} for OpenRouter) — a missing version segment produces a 404 on every request, not an auth error.")
                }
                Section("API Key") {
                    SecureField("API Key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    Button {
                        Task { await runTest() }
                    } label: {
                        HStack {
                            Text("Test Connection")
                            Spacer()
                            switch testState {
                            case .idle: EmptyView()
                            case .testing: ProgressView()
                            case .success: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            case .failure: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                            }
                        }
                    }
                    .disabled(!isValid || testState == .testing)
                    if case .failure(let message) = testState {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(existingID == nil ? "New Provider" : "Edit Provider")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!isValid)
                }
            }
        }
    }

    private func save() {
        let provider = AIProvider(id: existingID ?? UUID(), name: trimmedName, wire: wire, baseURL: baseURL, model: model, maxTokens: maxTokens)
        if existingID != nil {
            store.update(provider)
            store.setAPIKey(apiKey, for: provider)
        } else {
            store.add(provider, apiKey: apiKey)
        }
        dismiss()
    }

    private func runTest() async {
        testState = .testing
        // 300, not a handful — this is still just a connectivity probe, not a real request, but
        // reasoning models (see AIClient's OpenAI decoder) can burn a surprising number of
        // tokens on chain-of-thought before ever emitting a real answer token.
        let probeProvider = AIProvider(id: existingID ?? UUID(), name: trimmedName, wire: wire, baseURL: baseURL, model: model, maxTokens: 300)
        do {
            let stream = AIClient.stream(
                provider: probeProvider,
                apiKey: apiKey,
                system: "Reply with exactly one word: OK.",
                messages: [AIClient.ChatMessage(role: .user, text: "Say OK.")],
                tools: []
            )
            // AIClient.stream throws if the response never yields real text, so reaching here
            // without an exception means it succeeded.
            for try await _ in stream {}
            testState = .success
        } catch {
            testState = .failure(error.localizedDescription)
        }
    }
}
