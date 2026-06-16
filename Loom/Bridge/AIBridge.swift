import Foundation
import JavaScriptCore
import FoundationModels

// Implements Loom.ai.complete, .chat, .embed (stub), .search (LLM-ranked)
// complete/chat: apple (on-device SystemLanguageModel), claude (Anthropic API), gemini (Google AI API)
// search: LLM-powered relevance ranking using Apple on-device model
final class AIBridge {
    private let ctx: JSContext

    nonisolated init(ctx: JSContext) {
        self.ctx = ctx
    }

    nonisolated func makeObject() -> JSValue {
        let obj = JSValue(newObjectIn: ctx)!
        let capturedCtx = ctx

        // complete(prompt, opts?) → Promise<string>
        // opts: { provider: 'auto'|'apple'|'claude'|'gemini', maxTokens?, instructions? }
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

        obj.setObject(completeBlock, forKeyedSubscript: "complete" as NSString)
        obj.setObject(chatBlock,     forKeyedSubscript: "chat"     as NSString)
        obj.setObject(searchBlock,   forKeyedSubscript: "search"   as NSString)
        return obj
    }

    // MARK: - complete

    private func complete(prompt: String, opts: [String: Any]) async throws -> String {
        switch resolvedProvider(opts["provider"] as? String ?? "auto") {
        case .apple:  return try await appleComplete(prompt: prompt, opts: opts)
        case .claude: return try await claudeComplete(prompt: prompt, opts: opts)
        case .gemini: return try await geminiComplete(prompt: prompt, opts: opts)
        }
    }

    // MARK: - chat

    private func chat(messages: [[String: Any]], opts: [String: Any]) async throws -> String {
        switch resolvedProvider(opts["provider"] as? String ?? "auto") {
        case .apple:
            // Apple model is single-turn; concatenate history into a prompt
            let prompt = messages
                .map { "\(((($0["role"] as? String) ?? "user")).capitalized): \($0["content"] as? String ?? "")" }
                .joined(separator: "\n")
            return try await appleComplete(prompt: prompt, opts: opts)
        case .claude: return try await claudeChat(messages: messages, opts: opts)
        case .gemini: return try await geminiChat(messages: messages, opts: opts)
        }
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

    // MARK: - Claude (Anthropic API)

    private func claudeComplete(prompt: String, opts: [String: Any]) async throws -> String {
        try await claudeChat(messages: [["role": "user", "content": prompt]], opts: opts)
    }

    private func claudeChat(messages: [[String: Any]], opts: [String: Any]) async throws -> String {
        guard let apiKey = KeychainManager.load(service: KeychainManager.claudeAPIKeyService), !apiKey.isEmpty else {
            throw AIError.missingAPIKey("Claude")
        }
        let model = opts["model"] as? String ?? "claude-sonnet-4-6"
        let maxTokens = opts["maxTokens"] as? Int ?? 1024
        let body: [String: Any] = ["model": model, "max_tokens": maxTokens, "messages": messages]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.httpBody = bodyData
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = (json["content"] as? [[String: Any]])?.first?["text"] as? String else {
            throw AIError.badResponse(String(data: data, encoding: .utf8) ?? "")
        }
        return content
    }

    // MARK: - Gemini (Google AI API)

    private func geminiComplete(prompt: String, opts: [String: Any]) async throws -> String {
        try await geminiChat(messages: [["role": "user", "content": prompt]], opts: opts)
    }

    private func geminiChat(messages: [[String: Any]], opts: [String: Any]) async throws -> String {
        guard let apiKey = KeychainManager.load(service: KeychainManager.geminiAPIKeyService), !apiKey.isEmpty else {
            throw AIError.missingAPIKey("Gemini")
        }
        let model = opts["model"] as? String ?? "gemini-2.0-flash"
        let contents: [[String: Any]] = messages.map { m in
            let role = (m["role"] as? String) == "assistant" ? "model" : "user"
            return ["role": role, "parts": [["text": m["content"] as? String ?? ""]]]
        }
        let body: [String: Any] = ["contents": contents]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let urlStr = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"
        var req = URLRequest(url: URL(string: urlStr)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = bodyData
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let parts = ((json["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]],
              let content = parts.first?["text"] as? String else {
            throw AIError.badResponse(String(data: data, encoding: .utf8) ?? "")
        }
        return content
    }

    // MARK: - Helpers

    private enum Provider { case apple, claude, gemini }

    private func resolvedProvider(_ p: String) -> Provider {
        switch p {
        case "claude": return .claude
        case "gemini": return .gemini
        default:       return .apple
        }
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
    case missingAPIKey(String)
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .modelUnavailable:      return "Apple on-device AI model is not available on this device"
        case .missingAPIKey(let p):  return "\(p) API key not set — add it in Settings"
        case .badResponse(let body): return "Unexpected API response: \(body.prefix(200))"
        }
    }
}
