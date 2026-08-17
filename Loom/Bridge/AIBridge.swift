import Foundation
import JavaScriptCore
import FoundationModels

// Implements Loom.ai.complete, .chat, .search (LLM-ranked)
// complete/chat: 'apple'/'auto'/omitted runs the on-device SystemLanguageModel. Any other
// provider string names one the user configured in Settings, resolved through the shared
// AIProviderStore and called via AIClient — the same credential store and wire implementation
// the authoring assistant and inline completions use (ADR-015). Loom.ai owns no keys and no
// HTTP of its own.
// search: LLM-powered relevance ranking using Apple on-device model
final class AIBridge {
    private let ctx: JSContext

    // Matches NetworkBridge's caps — see ADR-025. nonisolated because the TaskGroup fan-out runs
    // off the main actor; without it these are an error under the Swift 6 language mode.
    nonisolated static let maxInFlight = 8
    nonisolated static let maxBatch = 64

    nonisolated init(ctx: JSContext) {
        self.ctx = ctx
    }

    nonisolated func makeObject() -> JSValue {
        let obj = JSValue(newObjectIn: ctx)!
        let capturedCtx = ctx

        // complete(prompt, opts?) → Promise<string>
        // opts: { provider?: 'apple' | <name of a provider configured in Settings>,
        //         model?, maxTokens?, instructions? }
        let completeBlock: @convention(block) (JSValue, JSValue) -> JSValue = { [weak self] promptVal, optsVal in
            guard let self else { return JSValue(undefinedIn: capturedCtx) }
            let prompt = promptVal.toString() ?? ""
            let opts = optsVal.isObject ? (optsVal.toDictionary() as? [String: Any] ?? [:]) : [:]
            return self.makePromise { resolve, reject in
                Task.detached {
                    do { resolve(try await self.complete(prompt: prompt, opts: opts)) }
                    catch { reject(error.localizedDescription) }
                }
            }
        }

        // chat(messages, opts?) → Promise<string>
        // messages: [{role:'user'|'assistant', content:'...'}]
        let chatBlock: @convention(block) (JSValue, JSValue) -> JSValue = { [weak self] msgsVal, optsVal in
            guard let self else { return JSValue(undefinedIn: capturedCtx) }
            let messages = (msgsVal.toArray() as? [[String: Any]]) ?? []
            let opts = optsVal.isObject ? (optsVal.toDictionary() as? [String: Any] ?? [:]) : [:]
            return self.makePromise { resolve, reject in
                Task.detached {
                    do { resolve(try await self.chat(messages: messages, opts: opts)) }
                    catch { reject(error.localizedDescription) }
                }
            }
        }

        // search(query, opts) → Promise<{text,score}[]>
        // opts: { corpus: string[] } — ranks corpus items by relevance to query using on-device model
        let searchBlock: @convention(block) (JSValue, JSValue) -> JSValue = { [weak self] queryVal, optsVal in
            guard let self else { return JSValue(undefinedIn: capturedCtx) }
            let query = queryVal.toString() ?? ""
            let opts = optsVal.isObject ? (optsVal.toDictionary() as? [String: Any] ?? [:]) : [:]
            let corpus = opts["corpus"] as? [String] ?? []
            return self.makePromise { resolve, reject in
                Task.detached {
                    do { resolve(try await self.search(query: query, corpus: corpus) as NSArray) }
                    catch { reject(error.localizedDescription) }
                }
            }
        }

        // completeAll(prompts, opts?) → Promise<{text, error}[]>
        //
        // makePromise blocks the script thread, so N sequential complete() calls cost the sum of
        // their latencies and Promise.all cannot recover it — the promises are already settled by
        // the time it sees them (ADR-025). One wait covers the whole batch here instead.
        // Measured on gpt-oss:120b: 7 completions, 67s sequential → 20s this way.
        //
        // Every element resolves. A prompt that fails carries its error string rather than
        // rejecting the batch and discarding the completions that did succeed.
        let completeAllBlock: @convention(block) (JSValue, JSValue) -> JSValue = { [weak self] promptsVal, optsVal in
            guard let self else { return JSValue(undefinedIn: capturedCtx) }
            let prompts = (promptsVal.toArray() as? [String]) ?? []
            let opts = optsVal.isObject ? (optsVal.toDictionary() as? [String: Any] ?? [:]) : [:]
            return self.makePromise { resolve, reject in
                guard !prompts.isEmpty else { resolve([Any]()); return }
                guard prompts.count <= Self.maxBatch else {
                    reject("Loom.ai.completeAll: \(prompts.count) prompts exceeds the limit of \(Self.maxBatch)")
                    return
                }
                Task.detached {
                    var out = [[String: Any]](
                        repeating: ["text": "", "error": ""], count: prompts.count
                    )
                    await withTaskGroup(of: (Int, String, String).self) { group in
                        var next = 0
                        // Hand-rolled window rather than adding all N at once: an unbounded fan-out
                        // at a provider is how a script earns a 429 for the whole batch.
                        func addTask(_ index: Int) {
                            group.addTask {
                                do { return (index, try await self.complete(prompt: prompts[index], opts: opts), "") }
                                catch { return (index, "", error.localizedDescription) }
                            }
                        }
                        while next < min(Self.maxInFlight, prompts.count) { addTask(next); next += 1 }
                        for await (index, text, err) in group {
                            out[index] = ["text": text, "error": err]
                            if next < prompts.count { addTask(next); next += 1 }
                        }
                    }
                    resolve(out)
                }
            }
        }

        obj.setObject(completeBlock,    forKeyedSubscript: "complete"    as NSString)
        obj.setObject(completeAllBlock, forKeyedSubscript: "completeAll" as NSString)
        obj.setObject(chatBlock,        forKeyedSubscript: "chat"        as NSString)
        obj.setObject(searchBlock,      forKeyedSubscript: "search"      as NSString)
        return obj
    }

    // MARK: - complete

    private func complete(prompt: String, opts: [String: Any]) async throws -> String {
        guard let provider = try resolveProvider(opts) else {
            // Deliberately passes the raw prompt, not the role-prefixed form chat() builds —
            // a single-turn completion shouldn't be dressed up as a transcript.
            return try await appleComplete(prompt: prompt, opts: opts)
        }
        return try await remote(provider: provider, messages: [.init(role: .user, text: prompt)], opts: opts)
    }

    // MARK: - chat

    private func chat(messages: [[String: Any]], opts: [String: Any]) async throws -> String {
        guard let provider = try resolveProvider(opts) else {
            // Apple model is single-turn; concatenate history into a prompt
            let prompt = messages
                .map { "\(((($0["role"] as? String) ?? "user")).capitalized): \($0["content"] as? String ?? "")" }
                .joined(separator: "\n")
            return try await appleComplete(prompt: prompt, opts: opts)
        }
        return try await remote(provider: provider, messages: messages.map(Self.chatMessage), opts: opts)
    }

    // MARK: - search (LLM-ranked)

    private func search(query: String, corpus: [String]) async throws -> [[String: Any]] {
        guard !corpus.isEmpty else { return [] }
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { throw AIError.modelUnavailable }

        let numbered = corpus.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let prompt = """
        Rate the relevance of each item to the query "\(query)" on a scale from 0.0 to 1.0.
        Return ONLY a JSON array of numbers in the same order as the items, e.g. [0.9, 0.2, 0.7].
        Items:
        \(numbered)
        """
        let session = LanguageModelSession(
            instructions: "You are a relevance scoring assistant. Respond only with a JSON array of numbers."
        )
        let response = try await session.respond(to: prompt)
        let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Parse the JSON array the model returns
        let scores: [Double]
        if let data = text.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [Double] {
            scores = arr
        } else {
            // Fallback: return corpus in original order with score 0
            scores = Array(repeating: 0.0, count: corpus.count)
        }

        return zip(corpus, scores)
            .map { ["text": $0.0, "score": $0.1] }
            .sorted { ($0["score"] as? Double ?? 0) > ($1["score"] as? Double ?? 0) }
    }

    // MARK: - Apple on-device

    private func appleComplete(prompt: String, opts: [String: Any]) async throws -> String {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { throw AIError.modelUnavailable }
        let instructions = opts["instructions"] as? String ?? ""
        let session = instructions.isEmpty
            ? LanguageModelSession()
            : LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: prompt)
        return response.content
    }

    // MARK: - Configured providers

    // AIClient streams; Loom.ai hands JS one string. Collecting it here is what lets Loom.ai and
    // the authoring assistant share a single wire implementation instead of maintaining two —
    // makePromise's semaphore simply waits a little longer.
    private func remote(
        provider: AIProvider, messages: [AIClient.ChatMessage], opts: [String: Any]
    ) async throws -> String {
        guard let apiKey = AIProviderStore.shared.apiKey(for: provider), !apiKey.isEmpty else {
            throw AIError.missingKey(provider.name)
        }
        // Per-call overrides of the provider's configured defaults. The id is unchanged, so the
        // Keychain lookup above still resolves.
        var provider = provider
        if let model = opts["model"] as? String, !model.isEmpty { provider.model = model }
        if let maxTokens = opts["maxTokens"] as? Int { provider.maxTokens = maxTokens }

        var text = ""
        for try await event in AIClient.stream(
            provider: provider,
            apiKey: apiKey,
            system: opts["instructions"] as? String ?? "",
            messages: messages,
            tools: []
        ) {
            if case .text(let chunk) = event { text += chunk }
        }
        return text
    }

    // MARK: - Helpers

    // nil means the on-device Apple model. Any other string names a provider the user configured
    // in Settings, matched case-insensitively — 'claude' and 'gemini' are no longer reserved
    // words, just the names the legacy-key migration happens to create (see AIProviderStore).
    private func resolveProvider(_ opts: [String: Any]) throws -> AIProvider? {
        let name = (opts["provider"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Case-insensitive throughout, so 'Apple' doesn't fall through to a name lookup and throw.
        if name.isEmpty || ["apple", "auto"].contains(name.lowercased()) { return nil }
        guard let provider = AIProviderStore.shared.providers.first(
            where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        ) else { throw AIError.unknownProvider(name) }
        return provider
    }

    private static func chatMessage(_ m: [String: Any]) -> AIClient.ChatMessage {
        AIClient.ChatMessage(
            role: (m["role"] as? String) == "assistant" ? .assistant : .user,
            text: m["content"] as? String ?? ""
        )
    }

    nonisolated private func makePromise(
        _ executor: (_ resolve: @escaping (Any?) -> Void, _ reject: @escaping (String) -> Void) -> Void
    ) -> JSValue {
        var resolvedVal: Any? = nil
        var rejectMsg: String? = nil
        let sema = DispatchSemaphore(value: 0)
        executor(
            { val in resolvedVal = val; sema.signal() },
            { msg in rejectMsg = msg; sema.signal() }
        )
        sema.wait()
        if let msg = rejectMsg {
            return ctx.objectForKeyedSubscript("__loomReject")?
                .call(withArguments: [msg]) ?? JSValue(undefinedIn: ctx)
        } else if let v = resolvedVal {
            return ctx.objectForKeyedSubscript("__loomResolve")?
                .call(withArguments: [v]) ?? JSValue(undefinedIn: ctx)
        } else {
            return ctx.objectForKeyedSubscript("__loomResolve")?
                .call(withArguments: []) ?? JSValue(undefinedIn: ctx)
        }
    }
}

private enum AIError: LocalizedError {
    case modelUnavailable
    case unknownProvider(String)
    case missingKey(String)

    var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            return "Apple on-device AI model is not available on this device"
        case .unknownProvider(let name):
            return "No AI provider named \u{201c}\(name)\u{201d} — add one in Settings, or use \u{201c}apple\u{201d} for the on-device model"
        case .missingKey(let name):
            return "No API key stored for provider \u{201c}\(name)\u{201d} — set it in Settings"
        }
    }
}
