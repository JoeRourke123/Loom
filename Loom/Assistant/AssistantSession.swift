import Foundation
import Observation

// Per-project chat state + the agent loop: stream a turn, execute any tool calls the model
// asked for, feed results back, repeat. Auto-apply — write_file tool calls take effect
// immediately, no confirmation step; AssistantBackup.snapshot (called once per user turn)
// is the only undo.
@Observable
@MainActor
final class AssistantSession {
    struct DisplayMessage: Identifiable {
        enum Kind { case userText, assistantText, toolCall }
        let id = UUID()
        var kind: Kind
        var text: String
    }

    let project: LoomProject
    private(set) var displayMessages: [DisplayMessage] = []
    private(set) var isStreaming = false
    var lastError: String?
    private(set) var tokensUsed: (input: Int, output: Int) = (0, 0)

    private var history: [AIClient.ChatMessage] = []
    private var currentTask: Task<Void, Never>?

    // Capped so a confused model can't loop forever burning tokens.
    private let maxToolRounds = 12

    init(project: LoomProject) {
        self.project = project
    }

    var hasSnapshot: Bool { AssistantBackup.hasSnapshot(project: project) }

    func send(_ text: String) {
        guard !isStreaming else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let provider = AIProviderStore.shared.selected,
              let apiKey = AIProviderStore.shared.apiKey(for: provider), !apiKey.isEmpty
        else {
            lastError = "No AI provider configured — add one in Settings."
            return
        }

        AssistantBackup.snapshot(project: project)
        displayMessages.append(DisplayMessage(kind: .userText, text: trimmed))
        history.append(AIClient.ChatMessage(role: .user, text: trimmed))
        lastError = nil

        currentTask = Task { await self.runLoop(provider: provider, apiKey: apiKey) }
    }

    func stop() {
        currentTask?.cancel()
        currentTask = nil
        isStreaming = false
    }

    func revertLastChanges() {
        AssistantBackup.revert(project: project)
    }

    // MARK: - Agent loop

    private func runLoop(provider: AIProvider, apiKey: String) async {
        isStreaming = true
        defer { isStreaming = false }

        for _ in 0..<maxToolRounds {
            do {
                let (text, toolCalls) = try await streamOneTurn(provider: provider, apiKey: apiKey)
                history.append(AIClient.ChatMessage(role: .assistant, text: text, toolCalls: toolCalls))
                guard !toolCalls.isEmpty else { return }

                for call in toolCalls {
                    let input = (try? JSONSerialization.jsonObject(with: Data(call.inputJSON.utf8))) as? [String: Any] ?? [:]
                    let result = await AssistantTools.execute(name: call.name, input: input, project: project)
                    displayMessages.append(DisplayMessage(kind: .toolCall, text: toolSummary(name: call.name, input: input, result: result)))
                    history.append(AIClient.ChatMessage(role: .toolResult, text: result, toolCallID: call.id))
                }
            } catch is CancellationError {
                return
            } catch {
                lastError = error.localizedDescription
                return
            }
        }
        lastError = "Stopped after \(maxToolRounds) tool-call rounds without a final answer — ask it to continue, or check it isn't stuck in a loop."
    }

    private func streamOneTurn(provider: AIProvider, apiKey: String) async throws -> (text: String, toolCalls: [AIClient.ToolCallRecord]) {
        let stream = AIClient.stream(
            provider: provider, apiKey: apiKey,
            system: AssistantSystemPrompt.text,
            messages: history, tools: AssistantTools.all
        )

        var text = ""
        var toolCalls: [AIClient.ToolCallRecord] = []
        var assistantIndex: Int?
        // Individual SSE chunks can be a handful of characters apiece — pushing every one straight
        // into displayMessages forces a full Markdown re-parse + re-render on each, which is what
        // made streaming responses feel janky. Flushing on a short timer instead caps that to
        // ~12/sec, which still reads as live. The final flush after the loop guarantees whatever
        // was buffered when the stream ended still lands, regardless of the throttle.
        var lastFlush = Date.distantPast
        let minFlushInterval: TimeInterval = 0.08

        func flush() {
            guard let index = assistantIndex else {
                displayMessages.append(DisplayMessage(kind: .assistantText, text: text))
                assistantIndex = displayMessages.count - 1
                return
            }
            displayMessages[index].text = text
        }

        for try await event in stream {
            switch event {
            case .text(let chunk):
                text += chunk
                let now = Date()
                if assistantIndex == nil || now.timeIntervalSince(lastFlush) > minFlushInterval {
                    flush()
                    lastFlush = now
                }
            case .toolCall(let id, let name, let input):
                let inputJSON = (try? JSONSerialization.data(withJSONObject: input)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                toolCalls.append(AIClient.ToolCallRecord(id: id, name: name, inputJSON: inputJSON))
            case .usage(let inputTokens, let outputTokens):
                tokensUsed.input += inputTokens
                tokensUsed.output += outputTokens
            case .done:
                break
            }
        }
        if assistantIndex != nil { flush() }
        return (text, toolCalls)
    }

    private func toolSummary(name: String, input: [String: Any], result: String) -> String {
        let firstLine = result.split(separator: "\n").first.map(String.init) ?? result
        switch name {
        case "read_doc": return "Read \(input["filename"] as? String ?? "doc")"
        case "read_file": return "Read \(input["filename"] as? String ?? "file")"
        case "write_file": return firstLine
        case "check_script": return "Checked \(input["filename"] as? String ?? "file") — \(firstLine)"
        case "run_script": return "Ran script — \(firstLine)"
        default: return name
        }
    }
}

// Keyed by project name, not `.id` — LoomProject.id is a fresh UUID on every
// ProjectStore.loadProjects(), so it can't identify a session across refreshes.
@MainActor
final class AssistantStore {
    static let shared = AssistantStore()
    private init() {}

    private var sessions: [String: AssistantSession] = [:]
    private var pendingPrompts: [String: String] = [:]

    func session(for project: LoomProject) -> AssistantSession {
        if let existing = sessions[project.name] { return existing }
        let session = AssistantSession(project: project)
        sessions[project.name] = session
        return session
    }

    // Used by the "Describe it" project-creation flow to hand the initial prompt to the
    // panel without threading it through LoomProject's navigationDestination(for:).
    func setPendingPrompt(_ prompt: String, for projectName: String) {
        pendingPrompts[projectName] = prompt
    }

    func consumePendingPrompt(for projectName: String) -> String? {
        defer { pendingPrompts[projectName] = nil }
        return pendingPrompts[projectName]
    }

    // Non-destructive peek — EditorContainerView uses this on appear to decide whether to
    // expand the panel and switch to the assistant tab, before AssistantPanelView itself
    // consumes (and sends) the prompt.
    func hasPendingPrompt(for projectName: String) -> Bool {
        pendingPrompts[projectName] != nil
    }
}

// authoring-rules.md + a manifest of the bundled doc pages, generated from DocCatalog so
// adding a doc page updates the assistant automatically. Built once — doc content doesn't
// change during a run.
private enum AssistantSystemPrompt {
    static let text: String = {
        let rules = Bundle.main.url(forResource: "authoring-rules", withExtension: "md")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
            ?? "# Loom Authoring Rules\n\n(authoring-rules.md failed to load)"

        let manifest = DocCategory.allCases.map { category -> String in
            let lines = DocCatalog.pages
                .filter { $0.category == category }
                .map { "- \($0.filename) — \($0.title)" }
                .joined(separator: "\n")
            return "### \(category.rawValue)\n\(lines)"
        }.joined(separator: "\n\n")

        // LoomAPICatalog (Loom/Editor/LoomAPICatalog.swift) is the same hand-written signature
        // list the editor's suggestion pills draw from — until now the assistant only saw doc
        // page *titles* here and had to read_doc for every real signature.
        let api = "### Loom.* API Signatures\n" + LoomAPICatalog.promptManifest

        return rules + "\n\n" + manifest + "\n\n" + api
    }()
}
