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
        return obj
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
