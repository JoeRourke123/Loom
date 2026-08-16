import Foundation
import Observation

// A user-defined AI provider. One list serves all three consumers — the authoring assistant,
// inline editor completions, and the Loom.ai script bridge (ADR-015; ADR-011 originally kept
// Loom.ai separate, which meant two credential stores and two Anthropic implementations).
// Free-text model field — no hardcoded model list, so any Anthropic-Messages- or
// OpenAI-Chat-Completions-compatible endpoint works (Anthropic, OpenAI, OpenRouter,
// Gemini's OpenAI-compatible endpoint, Ollama, etc).
struct AIProvider: Codable, Identifiable, Hashable {
    enum Wire: String, Codable, CaseIterable {
        case anthropic, openai

        var displayName: String {
            switch self {
            case .anthropic: return "Anthropic (Messages API)"
            case .openai: return "OpenAI (Chat Completions)"
            }
        }
    }

    let id: UUID
    var name: String
    var wire: Wire
    var baseURL: String
    var model: String
    var maxTokens: Int = 8192

    init(id: UUID = UUID(), name: String, wire: Wire, baseURL: String, model: String, maxTokens: Int = 8192) {
        self.id = id
        self.name = name
        self.wire = wire
        self.baseURL = baseURL
        self.model = model
        self.maxTokens = maxTokens
    }

    // Keyed by provider id so removing one provider can't collide with another's key.
    var keychainService: String { "uk.co.joerourke.Loom.assistant-provider.\(id.uuidString)" }
}

@Observable
final class AIProviderStore {
    static let shared = AIProviderStore()

    var providers: [AIProvider] {
        didSet { persistProviders() }
    }

    var selectedID: UUID? {
        didSet { UserDefaults.standard.set(selectedID?.uuidString, forKey: Self.selectedKey) }
    }

    var selected: AIProvider? {
        providers.first { $0.id == selectedID } ?? providers.first
    }

    /// Separate from `selectedID` — inline editor completions fire automatically on a debounce
    /// (see SuggestionEngine), so unlike the chat assistant's `selected` this deliberately has
    /// NO fallback to `providers.first`. An unset completions provider must mean "off", not
    /// "silently start billing whatever provider happens to be first in the list".
    var completionsID: UUID? {
        didSet { UserDefaults.standard.set(completionsID?.uuidString, forKey: Self.completionsKey) }
    }

    var completions: AIProvider? {
        providers.first { $0.id == completionsID }
    }

    private static let providersKey = "loom.assistant.providers"
    private static let selectedKey = "loom.assistant.selectedProvider"
    private static let completionsKey = "loom.completions.provider"
    private static let legacyMigrationKey = "loom.assistant.migratedLegacyKeys"

    private init() {
        // NB: adding a non-Optional stored property to AIProvider would make this `try?` fail
        // with keyNotFound on every previously-saved blob and silently wipe the user's whole
        // provider list — Swift's synthesized Codable ignores property defaults for missing
        // keys. New fields must be Optional, or this needs a custom init(from:).
        if let data = UserDefaults.standard.data(forKey: Self.providersKey),
           let decoded = try? JSONDecoder().decode([AIProvider].self, from: data) {
            providers = decoded
        } else {
            providers = []
        }
        if let idString = UserDefaults.standard.string(forKey: Self.selectedKey) {
            selectedID = UUID(uuidString: idString)
        }
        if let idString = UserDefaults.standard.string(forKey: Self.completionsKey) {
            completionsID = UUID(uuidString: idString)
        }
        migrateLegacyScriptKeys()
    }

    /// Loom.ai used to keep two API keys of its own under fixed Keychain services, entered in a
    /// separate Settings section (ADR-015 folded them into this store). One-shot on first launch
    /// after that change: turn whichever of those keys exist into ordinary providers — named
    /// "Claude" and "Gemini" so scripts already passing `{ provider: 'claude' }` keep resolving —
    /// then delete the old items so a key is never left sitting in two places.
    private func migrateLegacyScriptKeys() {
        guard !UserDefaults.standard.bool(forKey: Self.legacyMigrationKey) else { return }
        defer { UserDefaults.standard.set(true, forKey: Self.legacyMigrationKey) }

        let legacy: [(service: String, provider: AIProvider)] = [
            (
                "uk.co.joerourke.Loom.claude-api-key",
                AIProvider(
                    name: "Claude", wire: .anthropic,
                    baseURL: "https://api.anthropic.com", model: "claude-opus-5"
                )
            ),
            (
                // Gemini's OpenAI-compatible endpoint, so it rides the existing .openai wire
                // rather than needing a third dialect in AIClient.
                "uk.co.joerourke.Loom.gemini-api-key",
                AIProvider(
                    name: "Gemini", wire: .openai,
                    baseURL: "https://generativelanguage.googleapis.com/v1beta/openai",
                    model: "gemini-2.0-flash"
                )
            ),
        ]

        for (service, provider) in legacy {
            defer { KeychainManager.delete(service: service) }
            guard let key = KeychainManager.load(service: service), !key.isEmpty else { continue }
            // Don't shadow a provider the user already named "Claude"/"Gemini" by hand — theirs
            // wins, and the stale legacy key is dropped either way by the defer above.
            guard !providers.contains(where: {
                $0.name.caseInsensitiveCompare(provider.name) == .orderedSame
            }) else { continue }
            add(provider, apiKey: key)
        }
    }

    func add(_ provider: AIProvider, apiKey: String) {
        providers.append(provider)
        setAPIKey(apiKey, for: provider)
        if selectedID == nil { selectedID = provider.id }
    }

    func update(_ provider: AIProvider) {
        guard let index = providers.firstIndex(where: { $0.id == provider.id }) else { return }
        providers[index] = provider
    }

    func remove(_ provider: AIProvider) {
        providers.removeAll { $0.id == provider.id }
        KeychainManager.delete(service: provider.keychainService)
        if selectedID == provider.id { selectedID = providers.first?.id }
        // No fallback here either, matching completions' own "unset means off" rule above —
        // deleting the completions provider must turn completions off, not silently repoint at
        // whatever provider happens to be first.
        if completionsID == provider.id { completionsID = nil }
    }

    func apiKey(for provider: AIProvider) -> String? {
        KeychainManager.load(service: provider.keychainService)
    }

    func setAPIKey(_ key: String, for provider: AIProvider) {
        KeychainManager.save(key, service: provider.keychainService)
    }

    private func persistProviders() {
        guard let data = try? JSONEncoder().encode(providers) else { return }
        UserDefaults.standard.set(data, forKey: Self.providersKey)
    }
}
