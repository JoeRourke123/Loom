import Foundation
import JavaScriptCore

// Implements Loom.network.fetch(url, options?) -> Promise<Response>
// Response shape: { status, ok, headers, text(), json() }
final class NetworkBridge {
    private let ctx: JSContext
    private let project: LoomProject
    private let runLoop: CFRunLoop

    nonisolated init(ctx: JSContext, project: LoomProject, runLoop: CFRunLoop) {
        self.ctx = ctx
        self.project = project
        self.runLoop = runLoop
    }

    nonisolated func makeObject() -> JSValue {
        let obj = JSValue(newObjectIn: ctx)!

        let fetchBlock: @convention(block) (JSValue, JSValue) -> JSValue = { [weak self] urlVal, optsVal in
            guard let self else { return JSValue(undefinedIn: urlVal.context) }
            return self.fetch(urlVal: urlVal, optsVal: optsVal)
        }
        obj.setObject(fetchBlock, forKeyedSubscript: "fetch" as NSString)

        let fetchAllBlock: @convention(block) (JSValue) -> JSValue = { [weak self] requestsVal in
            guard let self else { return JSValue(undefinedIn: requestsVal.context) }
            return self.fetchAll(requestsVal: requestsVal)
        }
        obj.setObject(fetchAllBlock, forKeyedSubscript: "fetchAll" as NSString)
        return obj
    }

    // Caps. Not tuning knobs — a script that fans out 500 requests would exhaust the device's
    // socket budget and get itself rate-limited by whatever it is talking to.
    // nonisolated because the fan-out below runs off the main actor; without it these are an
    // error rather than a warning under the Swift 6 language mode.
    nonisolated static let maxInFlight = 8
    nonisolated static let maxBatch = 64

    // fetchAll(requests) -> Promise<Response[]>
    //
    // The point of this method is that makePromise blocks the script thread, so N sequential
    // fetch() calls cost the sum of their latencies and Promise.all cannot help — by the time it
    // sees them they are already settled (ADR-025). Here the fan-out happens below the semaphore:
    // one wait covers the whole batch.
    //
    // Results are positional and a failed element carries its own `error` rather than rejecting
    // the batch, because "five of seven succeeded" is the case worth keeping.
    nonisolated private func fetchAll(requestsVal: JSValue) -> JSValue {
        let items = (requestsVal.toArray() as? [[String: Any]]) ?? []

        return makePromise { resolve, reject in
            guard !items.isEmpty else { resolve([Any]()); return }
            guard items.count <= Self.maxBatch else {
                reject("Loom.network.fetchAll: \(items.count) requests exceeds the limit of \(Self.maxBatch)")
                return
            }

            var results = [[String: Any]?](repeating: nil, count: items.count)
            let lock = NSLock()
            let group = DispatchGroup()
            let gate = DispatchSemaphore(value: Self.maxInFlight)

            func finish(_ index: Int, _ value: [String: Any]) {
                lock.lock(); results[index] = value; lock.unlock()
                gate.signal()
                group.leave()
            }

            // Every enter() happens before the first leave() can, so group.notify cannot fire
            // early against a not-yet-populated group.
            for _ in items { group.enter() }

            DispatchQueue.global(qos: .userInitiated).async {
                for (index, item) in items.enumerated() {
                    gate.wait()
                    guard let urlStr = item["url"] as? String, let url = URL(string: urlStr) else {
                        finish(index, Self.failure("Invalid URL: \(item["url"] ?? "")"))
                        continue
                    }
                    var req = URLRequest(url: url)
                    if let method = item["method"] as? String { req.httpMethod = method }
                    // Same silent-drop rule as fetch(): one non-string value loses the whole
                    // dictionary, because that is what `as? [String: String]` does.
                    if let headers = item["headers"] as? [String: String] {
                        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
                    }
                    if let body = item["body"] as? String { req.httpBody = body.data(using: .utf8) }

                    URLSession.shared.dataTask(with: req) { data, response, error in
                        if let error {
                            finish(index, Self.failure(error.localizedDescription))
                            return
                        }
                        guard let http = response as? HTTPURLResponse else {
                            finish(index, Self.failure("No HTTP response"))
                            return
                        }
                        finish(index, [
                            "status": http.statusCode,
                            "ok": http.statusCode >= 200 && http.statusCode < 300,
                            "headers": (http.allHeaderFields as? [String: String]) ?? [:],
                            "_body": data.flatMap { String(data: $0, encoding: .utf8) } ?? "",
                            "error": ""
                        ])
                    }.resume()
                }
            }

            group.notify(queue: .global(qos: .userInitiated)) {
                // nil is unreachable — every slot is written before its leave() — but defaulting
                // beats force-unwrapping something the compiler cannot prove.
                resolve(results.map { $0 ?? Self.failure("No result") })
            }
        }
    }

    // status 0 marks "never reached the server", so `ok` is false and `_body` is empty without a
    // caller having to special-case a missing field.
    nonisolated private static func failure(_ message: String) -> [String: Any] {
        ["status": 0, "ok": false, "headers": [String: String](), "_body": "", "error": message]
    }

    nonisolated private func fetch(urlVal: JSValue, optsVal: JSValue) -> JSValue {
        let urlStr = urlVal.toString() ?? ""
        let opts = optsVal.isObject ? (optsVal.toDictionary() as? [String: Any] ?? [:]) : [:]

        return makePromise { resolve, reject in
            guard let url = URL(string: urlStr) else {
                reject("Invalid URL: \(urlStr)")
                return
            }
            var req = URLRequest(url: url)
            if let method = opts["method"] as? String { req.httpMethod = method }
            if let headers = opts["headers"] as? [String: String] {
                headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
            }
            if let body = opts["body"] as? String { req.httpBody = body.data(using: .utf8) }

            URLSession.shared.dataTask(with: req) { data, response, error in
                if let error {
                    reject(error.localizedDescription)
                    return
                }
                guard let http = response as? HTTPURLResponse else {
                    reject("No HTTP response")
                    return
                }
                let bodyStr = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let result: [String: Any] = [
                    "status": http.statusCode,
                    "ok": http.statusCode >= 200 && http.statusCode < 300,
                    "headers": (http.allHeaderFields as? [String: String]) ?? [:],
                    "_body": bodyStr
                ]
                resolve(result)
            }.resume()
        }
    }

    // Blocks the script thread until the executor calls resolve or reject,
    // then returns a pre-settled Promise so JSC can drain it as a microtask.
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
