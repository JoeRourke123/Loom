import Foundation

// Streaming, tool-using client for the authoring assistant. Two wire dialects (Anthropic
// Messages API, OpenAI Chat Completions API) behind one entry point — `AIProvider.wire`
// picks the dialect, everything else (base URL, model, key) is user-supplied, so any
// compatible endpoint works (Anthropic, OpenAI, OpenRouter, Ollama, ...).
//
// Deliberately separate from AIBridge (Loom.ai, the script-facing bridge): AIBridge's
// makePromise blocks a DispatchSemaphore waiting for a single result, which is structurally
// incompatible with incremental streaming — see AIBridge.swift's makePromise comment.
enum AIClient {

    // MARK: - Public types

    enum StreamEvent {
        case text(String)
        case toolCall(id: String, name: String, input: [String: Any])
        case usage(inputTokens: Int, outputTokens: Int)
        case done(stopReason: String?)
    }

    struct ChatMessage {
        enum Role { case user, assistant, toolResult }
        var role: Role
        var text: String = ""
        var toolCalls: [ToolCallRecord] = []   // only meaningful when role == .assistant
        var toolCallID: String? = nil          // only meaningful when role == .toolResult
    }

    struct ToolCallRecord: Hashable {
        let id: String
        let name: String
        let inputJSON: String
    }

    struct ToolSpec {
        let name: String
        let description: String
        let parameters: [String: Any]   // JSON schema object
    }

    enum ClientError: LocalizedError {
        case invalidBaseURL
        case httpError(Int, String)
        case emptyStream(String)

        var errorDescription: String? {
            switch self {
            case .invalidBaseURL: return "Invalid provider base URL"
            case .httpError(let code, let body): return "HTTP \(code): \(body.prefix(300))"
            case .emptyStream(let body):
                return body.isEmpty
                    ? "The server returned an empty response."
                    : "The server responded but sent no readable text. Raw response: \(body.prefix(300))"
            }
        }
    }

    // MARK: - Streaming entry point

    static func stream(
        provider: AIProvider,
        apiKey: String,
        system: String,
        messages: [ChatMessage],
        tools: [ToolSpec]
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeRequest(provider: provider, apiKey: apiKey, system: system, messages: messages, tools: tools)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        var body = ""
                        for try await line in bytes.lines { body += line }
                        throw ClientError.httpError(http.statusCode, body)
                    }

                    var anthropicState = AnthropicStreamState()
                    var openAIState = OpenAIStreamState()
                    var yieldedContent = false
                    var rawBody = ""
                    for try await line in bytes.lines {
                        if rawBody.utf8.count < 2000 { rawBody += line + "\n" }
                        guard let obj = parseSSELine(line) else { continue }
                        let events: [StreamEvent]
                        switch provider.wire {
                        case .anthropic: events = decodeAnthropicSSE(obj, state: &anthropicState)
                        case .openai: events = decodeOpenAISSE(obj, state: &openAIState)
                        }
                        for event in events {
                            if isUsableContent(event) { yieldedContent = true }
                            continuation.yield(event)
                        }
                    }
                    // A 2xx status that never produces text OR a tool call usually means the
                    // server sent an error payload instead of real content — either a plain JSON
                    // error body (parseSSELine silently drops any line without a "data:" prefix,
                    // so that vanishes with zero events at all) or a "valid" SSE chunk that only
                    // carries a finish_reason/error field. A tool-call-only turn (the model goes
                    // straight into calling a tool with no preceding text) is completely normal
                    // and must NOT trip this — only .usage/.done alone, with neither text nor a
                    // tool call ever appearing, counts as "nothing usable came back."
                    guard yieldedContent else {
                        throw ClientError.emptyStream(rawBody.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // Text and tool calls are real model output; usage/done alone (no text, no tool call) means
    // the turn produced nothing usable. Pulled out as its own pure function so the self-check
    // can exercise it directly — the emptyStream guard above lives inside a live network call
    // and can't be unit-tested any other way.
    private static func isUsableContent(_ event: StreamEvent) -> Bool {
        switch event {
        case .text, .toolCall: return true
        case .usage, .done: return false
        }
    }

    // MARK: - Request encoding

    private static func makeRequest(
        provider: AIProvider, apiKey: String, system: String, messages: [ChatMessage], tools: [ToolSpec]
    ) throws -> URLRequest {
        guard let base = URL(string: provider.baseURL) else { throw ClientError.invalidBaseURL }

        var url: URL
        var body: [String: Any]
        var headers = ["Content-Type": "application/json"]

        switch provider.wire {
        case .anthropic:
            url = base.appendingPathComponent("v1/messages")
            body = [
                "model": provider.model,
                "max_tokens": provider.maxTokens,
                "system": system,
                "stream": true,
                "messages": anthropicMessages(from: messages),
            ]
            if !tools.isEmpty { body["tools"] = anthropicTools(tools) }
            headers["x-api-key"] = apiKey
            headers["anthropic-version"] = "2023-06-01"

        case .openai:
            url = base.appendingPathComponent("chat/completions")
            body = [
                "model": provider.model,
                "max_tokens": provider.maxTokens,
                "stream": true,
                "messages": openAIMessages(system: system, from: messages),
            ]
            if !tools.isEmpty { body["tools"] = openAITools(tools) }
            headers["Authorization"] = "Bearer \(apiKey)"
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        for (key, value) in headers { req.setValue(value, forHTTPHeaderField: key) }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    // Anthropic requires strict user/assistant role alternation, so consecutive tool-result
    // turns (one per tool call the model made) collapse into a single user message with
    // multiple tool_result content blocks.
    private static func anthropicMessages(from messages: [ChatMessage]) -> [[String: Any]] {
        var result: [[String: Any]] = []
        var i = 0
        while i < messages.count {
            let m = messages[i]
            switch m.role {
            case .user:
                result.append(["role": "user", "content": m.text])
                i += 1
            case .assistant:
                var content: [[String: Any]] = []
                if !m.text.isEmpty { content.append(["type": "text", "text": m.text]) }
                for call in m.toolCalls {
                    let input = (try? JSONSerialization.jsonObject(with: Data(call.inputJSON.utf8))) as? [String: Any] ?? [:]
                    content.append(["type": "tool_use", "id": call.id, "name": call.name, "input": input])
                }
                result.append(["role": "assistant", "content": content])
                i += 1
            case .toolResult:
                var blocks: [[String: Any]] = []
                while i < messages.count, messages[i].role == .toolResult {
                    blocks.append(["type": "tool_result", "tool_use_id": messages[i].toolCallID ?? "", "content": messages[i].text])
                    i += 1
                }
                result.append(["role": "user", "content": blocks])
            }
        }
        return result
    }

    // OpenAI wants one {role:"tool"} message per tool call — no merging needed.
    private static func openAIMessages(system: String, from messages: [ChatMessage]) -> [[String: Any]] {
        var result: [[String: Any]] = [["role": "system", "content": system]]
        for m in messages {
            switch m.role {
            case .user:
                result.append(["role": "user", "content": m.text])
            case .assistant:
                var msg: [String: Any] = ["role": "assistant", "content": m.text]
                if !m.toolCalls.isEmpty {
                    msg["tool_calls"] = m.toolCalls.map {
                        ["id": $0.id, "type": "function", "function": ["name": $0.name, "arguments": $0.inputJSON]]
                    }
                }
                result.append(msg)
            case .toolResult:
                result.append(["role": "tool", "tool_call_id": m.toolCallID ?? "", "content": m.text])
            }
        }
        return result
    }

    private static func anthropicTools(_ tools: [ToolSpec]) -> [[String: Any]] {
        tools.map { ["name": $0.name, "description": $0.description, "input_schema": $0.parameters] }
    }

    private static func openAITools(_ tools: [ToolSpec]) -> [[String: Any]] {
        tools.map { ["type": "function", "function": ["name": $0.name, "description": $0.description, "parameters": $0.parameters]] }
    }

    // MARK: - SSE line parsing (shared by both wires)

    private static func parseSSELine(_ line: String) -> [String: Any]? {
        guard line.hasPrefix("data:") else { return nil }
        let jsonStr = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard jsonStr != "[DONE]", let data = jsonStr.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    // MARK: - Anthropic SSE decoding

    private struct AnthropicStreamState {
        var accumulatingTool = false
        var toolID: String?
        var toolName: String?
        var toolJSON = ""
        var stopReason: String?
    }

    private static func decodeAnthropicSSE(_ obj: [String: Any], state: inout AnthropicStreamState) -> [StreamEvent] {
        guard let type = obj["type"] as? String else { return [] }
        switch type {
        case "content_block_start":
            guard let block = obj["content_block"] as? [String: Any], block["type"] as? String == "tool_use" else { return [] }
            state.accumulatingTool = true
            state.toolID = block["id"] as? String
            state.toolName = block["name"] as? String
            state.toolJSON = ""
            return []

        case "content_block_delta":
            guard let delta = obj["delta"] as? [String: Any] else { return [] }
            switch delta["type"] as? String {
            case "text_delta":
                return [.text(delta["text"] as? String ?? "")]
            case "input_json_delta":
                state.toolJSON += (delta["partial_json"] as? String ?? "")
                return []
            default:
                return []
            }

        case "content_block_stop":
            guard state.accumulatingTool, let id = state.toolID, let name = state.toolName else { return [] }
            let input = (try? JSONSerialization.jsonObject(with: Data(state.toolJSON.utf8))) as? [String: Any] ?? [:]
            state.accumulatingTool = false
            state.toolID = nil
            state.toolName = nil
            state.toolJSON = ""
            return [.toolCall(id: id, name: name, input: input)]

        case "message_delta":
            var events: [StreamEvent] = []
            if let delta = obj["delta"] as? [String: Any], let stopReason = delta["stop_reason"] as? String {
                state.stopReason = stopReason
            }
            if let usage = obj["usage"] as? [String: Any], let outputTokens = usage["output_tokens"] as? Int {
                events.append(.usage(inputTokens: 0, outputTokens: outputTokens))
            }
            return events

        case "message_start":
            guard let message = obj["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any],
                  let inputTokens = usage["input_tokens"] as? Int
            else { return [] }
            return [.usage(inputTokens: inputTokens, outputTokens: 0)]

        case "message_stop":
            return [.done(stopReason: state.stopReason)]

        default:
            return []
        }
    }

    // MARK: - OpenAI SSE decoding

    private struct OpenAIStreamState {
        struct PendingCall { var id: String?; var name: String?; var args = "" }
        var calls: [Int: PendingCall] = [:]
    }

    private static func decodeOpenAISSE(_ obj: [String: Any], state: inout OpenAIStreamState) -> [StreamEvent] {
        var events: [StreamEvent] = []
        if let usage = obj["usage"] as? [String: Any] {
            events.append(.usage(
                inputTokens: usage["prompt_tokens"] as? Int ?? 0,
                outputTokens: usage["completion_tokens"] as? Int ?? 0
            ))
        }
        guard let choices = obj["choices"] as? [[String: Any]], let choice = choices.first else { return events }

        if let delta = choice["delta"] as? [String: Any] {
            if let content = delta["content"] as? String, !content.isEmpty {
                events.append(.text(content))
            }
            // Reasoning models (GLM, DeepSeek-R1, QwQ, ...) stream chain-of-thought through a
            // separate field before "content" ever starts filling — field name varies by
            // provider ("reasoning" vs "reasoning_content"). Surfaced as plain text rather than
            // a distinct "thinking" UI state; without this it silently vanishes, which can burn
            // an entire token budget on reasoning before any real answer text ever appears.
            if let reasoning = (delta["reasoning"] as? String) ?? (delta["reasoning_content"] as? String), !reasoning.isEmpty {
                events.append(.text(reasoning))
            }
            if let toolCalls = delta["tool_calls"] as? [[String: Any]] {
                for call in toolCalls {
                    guard let index = call["index"] as? Int else { continue }
                    var pending = state.calls[index] ?? .init()
                    if let id = call["id"] as? String { pending.id = id }
                    if let function = call["function"] as? [String: Any] {
                        if let name = function["name"] as? String { pending.name = name }
                        if let args = function["arguments"] as? String { pending.args += args }
                    }
                    state.calls[index] = pending
                }
            }
        }

        if let finishReason = choice["finish_reason"] as? String {
            for index in state.calls.keys.sorted() {
                guard let pending = state.calls[index], let id = pending.id, let name = pending.name else { continue }
                let input = (try? JSONSerialization.jsonObject(with: Data(pending.args.utf8))) as? [String: Any] ?? [:]
                events.append(.toolCall(id: id, name: name, input: input))
            }
            state.calls.removeAll()
            events.append(.done(stopReason: finishReason))
        }
        return events
    }

    // MARK: - Self-check

    #if DEBUG
    @discardableResult
    static func runSelfCheck() -> Bool {
        var failures: [String] = []
        func check(_ name: String, _ condition: @autoclosure () -> Bool) {
            if !condition() { failures.append(name) }
        }
        func hasText(_ events: [StreamEvent], _ text: String) -> Bool {
            events.contains { if case .text(let t) = $0 { return t == text }; return false }
        }
        func hasToolCall(_ events: [StreamEvent], id: String, name: String, filenameArg: String) -> Bool {
            events.contains {
                if case .toolCall(let cid, let cname, let input) = $0 {
                    return cid == id && cname == name && (input["filename"] as? String) == filenameArg
                }
                return false
            }
        }
        func stopReason(_ events: [StreamEvent]) -> String? {
            for event in events { if case .done(let reason) = event { return reason } }
            return nil
        }

        var aState = AnthropicStreamState()
        let anthropicTranscript = [
            #"data: {"type":"message_start","message":{"usage":{"input_tokens":10}}}"#,
            #"data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}"#,
            #"data: {"type":"content_block_stop","index":0}"#,
            #"data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_1","name":"read_doc","input":{}}}"#,
            #"data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"filename\":\"db.md\"}"}}"#,
            #"data: {"type":"content_block_stop","index":1}"#,
            #"data: {"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":12}}"#,
            #"data: {"type":"message_stop"}"#,
        ]
        let aEvents = anthropicTranscript.compactMap(parseSSELine).flatMap { decodeAnthropicSSE($0, state: &aState) }
        check("anthropic.text", hasText(aEvents, "Hello"))
        check("anthropic.toolCall", hasToolCall(aEvents, id: "toolu_1", name: "read_doc", filenameArg: "db.md"))
        check("anthropic.done", stopReason(aEvents) == "tool_use")

        var oState = OpenAIStreamState()
        let openAITranscript = [
            #"data: {"choices":[{"index":0,"delta":{"content":"Hi"}}]}"#,
            #"data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"call_1","function":{"name":"read_doc","arguments":""}}]}}]}"#,
            #"data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"filename\":"}}]}}]}"#,
            #"data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"db.md\"}"}}]}}]}"#,
            #"data: {"choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}"#,
            #"data: [DONE]"#,
        ]
        let oEvents = openAITranscript.compactMap(parseSSELine).flatMap { decodeOpenAISSE($0, state: &oState) }
        check("openai.text", hasText(oEvents, "Hi"))
        check("openai.toolCall", hasToolCall(oEvents, id: "call_1", name: "read_doc", filenameArg: "db.md"))
        check("openai.done", stopReason(oEvents) == "tool_calls")

        // Reasoning models (GLM, DeepSeek-R1, ...) stream chain-of-thought via a "reasoning"
        // field with content:"" — regression test for a real bug: this used to vanish silently.
        var rState = OpenAIStreamState()
        let reasoningTranscript = [
            #"data: {"choices":[{"index":0,"delta":{"role":"assistant","content":"","reasoning":"Thinking"}}]}"#,
            #"data: {"choices":[{"index":0,"delta":{"content":"Answer"}}]}"#,
        ]
        let rEvents = reasoningTranscript.compactMap(parseSSELine).flatMap { decodeOpenAISSE($0, state: &rState) }
        check("openai.reasoning", hasText(rEvents, "Thinking") && hasText(rEvents, "Answer"))

        // Regression test for a real bug that shipped and broke a live device: a tool-call-only
        // turn (model goes straight into calling a tool, no preceding text at all — completely
        // normal) must count as usable content. An earlier "fix" required actual .text and threw
        // ClientError.emptyStream on every legitimate tool call, which the self-check above never
        // caught because its openAITranscript happens to have text ("Hi") alongside the tool call.
        var toolOnlyState = OpenAIStreamState()
        let toolOnlyTranscript = [
            #"data: {"choices":[{"index":0,"delta":{"role":"assistant","content":"","tool_calls":[{"index":0,"id":"call_2","function":{"name":"write_file","arguments":""}}]}}]}"#,
            #"data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"filename\":\"main.ts\"}"}}]}}]}"#,
            #"data: {"choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}"#,
        ]
        let toolOnlyEvents = toolOnlyTranscript.compactMap(parseSSELine).flatMap { decodeOpenAISSE($0, state: &toolOnlyState) }
        check("openai.toolCallOnly.noText", !hasText(toolOnlyEvents, "anything"))
        check("openai.toolCallOnly.hasToolCall", hasToolCall(toolOnlyEvents, id: "call_2", name: "write_file", filenameArg: "main.ts"))
        check("openai.toolCallOnly.countsAsUsableContent", toolOnlyEvents.contains { isUsableContent($0) })
        check("emptyContent.doneAloneNotUsable", !isUsableContent(.done(stopReason: "stop")))
        check("emptyContent.usageAloneNotUsable", !isUsableContent(.usage(inputTokens: 1, outputTokens: 1)))

        if !failures.isEmpty {
            print("⚠️ AIClient.runSelfCheck FAILED: \(failures.joined(separator: ", "))")
        }
        return failures.isEmpty
    }
    #endif
}
