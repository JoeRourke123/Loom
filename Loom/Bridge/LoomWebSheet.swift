import Foundation
import JavaScriptCore
import UIKit
import WebKit

// Loom.ui.web() — an htmx-driven web sheet.
//
// The request loop runs in JS, on the script thread, inside the calling handler's own async chain
// (see `serveJS` below, wired up in UIBridge.makeObject). It cannot run in Swift: JSC only drains
// microtasks when the outermost JS entry unwinds, so a nested JSValue.call() from a native block
// never drains and Swift could never await an async route handler. LoomBridge.inject() records the
// same constraint for makePromise.
//
// Threading: only the script thread touches the JSContext. Everything here moves plain Swift
// values — the queue is condition-guarded; the scheme handler, its live-task map, and the sheet
// controller are main-thread only.

// MARK: - Request

struct WebRequest {
    let id: Int
    let method: String
    let path: String
    let query: [String: String]
    let body: [String: String]
    let headers: [String: String]

    var jsObject: NSDictionary {
        ["id": id, "method": method, "path": path, "query": query, "body": body, "headers": headers]
    }
}

// MARK: - Queue

// FIFO handoff from the main thread (WebKit) to the script thread (the JS serve loop).
final class WebRequestQueue {
    private let cond = NSCondition()
    private var pending: [WebRequest] = []
    private var closed = false

    func enqueue(_ request: WebRequest) {
        cond.lock(); defer { cond.unlock() }
        guard !closed else { return }
        pending.append(request)
        cond.signal()
    }

    // Parks the script thread until a request arrives or the sheet closes. Returning nil is what
    // ends the JS serve loop, so it must only happen once closed *and* drained.
    func next() -> WebRequest? {
        cond.lock(); defer { cond.unlock() }
        while pending.isEmpty && !closed { cond.wait() }
        return pending.isEmpty ? nil : pending.removeFirst()
    }

    func close() {
        cond.lock(); defer { cond.unlock() }
        closed = true
        cond.broadcast()
    }

    var isClosed: Bool {
        cond.lock(); defer { cond.unlock() }
        return closed
    }
}

// MARK: - Scheme handler

final class LoomWebSchemeHandler: NSObject, WKURLSchemeHandler {
    // Deliberately not "loom" — that's the app's deep-link scheme (DeepLinkHandler).
    static let scheme = "loomweb"

    private let queue: WebRequestQueue
    private let document: String
    // Main thread only. Responding to a task WebKit has already passed to stop() raises an ObjC
    // exception — a hard crash — so a task is only ever touched while it is still in this map.
    private var liveTasks: [Int: WKURLSchemeTask] = [:]
    private var lastID = 0

    init(queue: WebRequestQueue, document: String) {
        self.queue = queue
        self.document = document
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else { return }
        let path = url.path.isEmpty ? "/" : url.path

        // Served straight from Swift, never queued. Routing the page load or htmx itself through
        // the JS loop would deadlock — the load would wait on a serve loop that cannot start until
        // the load completes.
        if path == "/" {
            reply(urlSchemeTask, url: url, mime: "text/html", data: Data(Self.inject(into: document).utf8))
            return
        }
        if path == "/htmx.min.js" {
            reply(urlSchemeTask, url: url, mime: "text/javascript", data: Self.htmxSource())
            return
        }
        // A request racing the sheet's dismissal gets an answer rather than hanging forever.
        guard !queue.isClosed else {
            reply(urlSchemeTask, url: url, mime: "text/plain", status: 503, data: Data("Web sheet closed".utf8))
            return
        }

        lastID += 1
        liveTasks[lastID] = urlSchemeTask
        queue.enqueue(Self.request(id: lastID, from: urlSchemeTask.request, path: path, url: url))
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        guard let id = liveTasks.first(where: { $0.value as AnyObject === urlSchemeTask as AnyObject })?.key
        else { return }
        liveTasks.removeValue(forKey: id)
    }

    // Main thread only.
    func respond(id: Int, status: Int, body: String) {
        guard let task = liveTasks.removeValue(forKey: id), let url = task.request.url else { return }
        reply(task, url: url, mime: "text/html", status: status, data: Data(body.utf8))
    }

    // Main thread only.
    func failAll() {
        let error = NSError(
            domain: "Loom", code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Web sheet closed"]
        )
        for task in liveTasks.values { task.didFailWithError(error) }
        liveTasks.removeAll()
    }

    private func reply(_ task: WKURLSchemeTask, url: URL, mime: String, status: Int = 200, data: Data) {
        let response = HTTPURLResponse(
            url: url, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "\(mime); charset=utf-8", "Content-Length": String(data.count)]
        )!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    // MARK: Request building / parsing

    static func request(id: Int, from urlRequest: URLRequest, path: String, url: URL) -> WebRequest {
        let method = urlRequest.httpMethod?.uppercased() ?? "GET"
        let query = parseFormEncoded(URLComponents(url: url, resolvingAgainstBaseURL: false)?.query ?? "")
        var body = parseBody(urlRequest)
        // WebKit does not populate httpBody on a custom-scheme task, so hx-post params would
        // otherwise vanish entirely. serveJS sets htmx.config.methodsThatUseUrlParams for every
        // method, which puts them in the query string instead; mirroring them into body keeps the
        // obvious handler code (req.body.title after an hx-post) working.
        if body.isEmpty && method != "GET" { body = query }
        return WebRequest(
            id: id, method: method, path: path, query: query, body: body,
            headers: urlRequest.allHTTPHeaderFields ?? [:]
        )
    }

    static func parseBody(_ urlRequest: URLRequest) -> [String: String] {
        guard let data = urlRequest.httpBody, !data.isEmpty else { return [:] }
        let contentType = urlRequest.value(forHTTPHeaderField: "Content-Type") ?? ""
        if contentType.contains("application/json") {
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
            // ponytail: flattens nested JSON values to their description. htmx posts flat forms by
            // default; give structured data its own query param if shape matters.
            return obj.mapValues { $0 as? String ?? String(describing: $0) }
        }
        return parseFormEncoded(String(data: data, encoding: .utf8) ?? "")
    }

    static func parseFormEncoded(_ raw: String) -> [String: String] {
        var out: [String: String] = [:]
        for pair in raw.split(separator: "&", omittingEmptySubsequences: true) {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let rawKey = parts.first, !rawKey.isEmpty else { continue }
            out[decode(String(rawKey))] = parts.count > 1 ? decode(String(parts[1])) : ""
        }
        return out
    }

    // '+' means space in form encoding and must be swapped before percent-decoding, so a literal
    // plus sent as %2B survives.
    private static func decode(_ s: String) -> String {
        let spaced = s.replacingOccurrences(of: "+", with: " ")
        return spaced.removingPercentEncoding ?? spaced
    }

    // MARK: Document

    private static let configTag =
        "<script>htmx.config.methodsThatUseUrlParams = [\"get\", \"post\", \"put\", \"patch\", \"delete\"];</script>"

    // A template that forgets the script tag would otherwise be a silently dead page with no error
    // anywhere — and the assistant will forget it. When the author supplies their own tag we append
    // only the config, which still runs after theirs since scripts execute in document order.
    static func inject(into document: String) -> String {
        document.contains("htmx.min.js")
            ? document + "\n" + configTag
            : "<script src=\"/htmx.min.js\"></script>\n" + configTag + "\n" + document
    }

    static func htmxSource() -> Data {
        guard let url = Bundle.main.url(forResource: "htmx.min", withExtension: "js"),
              let data = try? Data(contentsOf: url)
        else { return Data() }
        return data
    }
}

// MARK: - Navigation policy

// WKWebView holds its navigationDelegate weakly, so LoomWebSession retains this.
final class LoomWebNavigationDelegate: NSObject, WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if url.scheme == LoomWebSchemeHandler.scheme {
            decisionHandler(.allow)
            return
        }
        // Anything else would leave the sheet: hand http(s) to the system browser, drop the rest.
        decisionHandler(.cancel)
        if url.scheme == "http" || url.scheme == "https" {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Sheet controller

final class LoomWebSheetController: UIViewController {
    private let webView: WKWebView
    private let onDismiss: () -> Void

    init(webView: WKWebView, title: String, onDismiss: @escaping () -> Void) {
        self.webView = webView
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        webView.frame = view.bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(webView)
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: self, action: #selector(doneTapped)
        )
    }

    @objc private func doneTapped() { dismiss(animated: true) }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Being covered by another modal (a Loom.ui.alert from inside a route handler) leaves the
        // window attached; actually going away does not. One check covers Done, swipe-to-dismiss,
        // programmatic dismiss and parent teardown.
        if view.window == nil { onDismiss() }
    }
}

// MARK: - Session

// One live web sheet. Created on the script thread by Loom.ui.web's `open`; its handler and
// controller are only ever touched on the main thread.
final class LoomWebSession {
    let queue = WebRequestQueue()
    private let document: String
    private let navigationDelegate = LoomWebNavigationDelegate()
    private var handler: LoomWebSchemeHandler?
    private var controller: LoomWebSheetController?

    init(document: String) { self.document = document }

    @MainActor
    func present(from presenter: UIViewController, title: String) {
        let handler = LoomWebSchemeHandler(queue: queue, document: document)
        self.handler = handler

        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(handler, forURLScheme: LoomWebSchemeHandler.scheme)
        // No cookies or localStorage carried between runs or projects. There is deliberately no
        // WKScriptMessageHandler either — the routes map is the entire attack surface, and the
        // author declared every entry in it.
        config.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = navigationDelegate
        #if DEBUG
        webView.isInspectable = true
        #endif

        let sheet = LoomWebSheetController(webView: webView, title: title) { [weak self] in
            self?.queue.close()
        }
        controller = sheet

        let nav = UINavigationController(rootViewController: sheet)
        nav.modalPresentationStyle = .pageSheet
        nav.sheetPresentationController?.detents = [.large()]

        // present() during another presentation's transition can silently no-op. The Run button
        // expands the console panel sheet immediately before starting the run, so that transition
        // is frequently still in flight by the time we get here.
        if let coordinator = presenter.transitionCoordinator {
            coordinator.animate(alongsideTransition: nil) { _ in presenter.present(nav, animated: true) }
        } else {
            presenter.present(nav, animated: true)
        }

        // Served from the scheme handler rather than loadHTMLString(_:baseURL:), which does not
        // reliably route subresources through the handler. This is what makes a relative
        // hx-get="/todos" resolve to loomweb://app/todos.
        webView.load(URLRequest(url: URL(string: "\(LoomWebSchemeHandler.scheme)://app/")!))
    }

    func respond(id: Int, status: Int, body: String) {
        DispatchQueue.main.async { [weak self] in
            self?.handler?.respond(id: id, status: status, body: body)
        }
    }

    // Called from the JS loop's `finally`. Idempotent — viewDidDisappear may already have closed
    // the queue, and closing twice is harmless.
    func finish() {
        queue.close()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.handler?.failAll()
            if let controller = self.controller, controller.view.window != nil {
                controller.dismiss(animated: true)
            }
            self.controller = nil
            self.handler = nil
        }
    }
}

// MARK: - The JS serve loop

enum LoomWebSheet {
    // A factory taking the four native blocks and returning the async function that becomes
    // Loom.ui.web. Closing over the blocks avoids adding four more globals to the script context.
    //
    // String(r) is what lets the `html` tag's {__html, toString} drop in with no special case.
    // The per-route try/catch means one failing route never kills the loop — the same principle as
    // __loom_collect_widget__'s catch in ModuleBundler.
    static let serveJS = """
    (function(open, next, respond, close) {
      return async function(opts) {
        opts = opts || {};
        var routes = opts.routes || {};
        var opened = await open(
          typeof opts.template === 'string' ? opts.template : null,
          typeof opts.html === 'string' ? opts.html : null,
          typeof opts.title === 'string' ? opts.title : null
        );
        if (!opened) { close(); return; }
        try {
          while (true) {
            var req = await next();
            if (!req) break;
            var fn = routes[req.method + ' ' + req.path] || routes[req.path];
            var status = 200;
            var body;
            if (typeof fn !== 'function') {
              status = 404;
              body = 'No route for ' + req.method + ' ' + req.path;
            } else {
              try {
                var r = await fn(req);
                body = (r === undefined || r === null) ? '' : String(r);
              } catch (e) {
                var msg = (e && e.message) ? e.message : String(e);
                Loom.log.error('Loom.ui.web ' + req.method + ' ' + req.path + ': ' + msg);
                body = '<pre style="color:#c00;white-space:pre-wrap">' + __loom_esc__(msg) + '</pre>';
              }
            }
            respond(req.id, status, body);
          }
        } finally {
          close();
        }
      };
    })
    """

    // Mirrors AssistantTools.resolvedProjectFileURL: no path components, no leading dot, and the
    // parent re-derived from the standardized URL so nothing resolves outside the project folder.
    static func templateURL(_ name: String, project: LoomProject) -> URL? {
        guard !name.isEmpty, !name.contains("/"), !name.hasPrefix(".") else { return nil }
        let url = project.folderURL.appendingPathComponent(name)
        guard url.standardizedFileURL.deletingLastPathComponent() == project.folderURL.standardizedFileURL
        else { return nil }
        return url
    }
}

// MARK: - Self-check

#if DEBUG
extension LoomWebSheet {
    @discardableResult
    static func runSelfCheck() -> Bool {
        var failures: [String] = []
        func check(_ name: String, _ condition: @autoclosure () -> Bool) {
            if !condition() { failures.append(name) }
        }

        // --- Form/query parsing ---
        let q = LoomWebSchemeHandler.parseFormEncoded("a=1&b=hello+world&c=%C3%A9&d=")
        check("parse.count", q.count == 4)
        check("parse.plusIsSpace", q["b"] == "hello world")
        check("parse.percent", q["c"] == "é")
        check("parse.emptyValue", q["d"] == "")
        // %2B must survive the '+'-to-space swap as a literal plus.
        check("parse.plusLiteral", LoomWebSchemeHandler.parseFormEncoded("x=a%2Bb")["x"] == "a+b")
        check("parse.empty", LoomWebSchemeHandler.parseFormEncoded("").isEmpty)

        // --- htmx injection ---
        let bare = LoomWebSchemeHandler.inject(into: "<p>hi</p>")
        check("inject.addsScript", bare.contains("<script src=\"/htmx.min.js\">"))
        check("inject.addsConfig", bare.contains("methodsThatUseUrlParams"))
        let own = LoomWebSchemeHandler.inject(into: "<script src=\"/htmx.min.js\"></script><p>hi</p>")
        check("inject.noDuplicateScript", own.components(separatedBy: "/htmx.min.js").count == 2)
        check("inject.configWhenAuthorSupplied", own.contains("methodsThatUseUrlParams"))

        // --- The serve loop, end to end ---
        // Pins routing, the method-prefix fallback, error isolation, String(r) coercion, and that
        // the whole chain settles inside one evaluateScript drain. If JSC's microtask model ever
        // changes, this is what fails.
        if let vm = JSVirtualMachine(), let ctx = JSContext(virtualMachine: vm) {
            var exception: String?
            ctx.exceptionHandler = { _, ex in exception = ex?.toString() }
            ctx.evaluateScript("var __errors__ = []; var __loomResolve = function(v){ return Promise.resolve(v); };")
            ctx.evaluateScript("var Loom = { log: { error: function(m){ __errors__.push(m); } } };")
            ctx.evaluateScript(ModuleBundler.loomCoreStub) // brings in __loom_esc__

            func req(_ id: Int, _ method: String, _ path: String) -> NSDictionary {
                ["id": id, "method": method, "path": path,
                 "query": [String: String](), "body": [String: String](), "headers": [String: String]()]
            }
            var queued: [NSDictionary] = [
                req(1, "GET", "/sync"), req(2, "GET", "/async"),
                req(3, "POST", "/throws"), req(4, "GET", "/missing"),
            ]
            var responses: [(id: Int, status: Int, body: String)] = []
            var closed = false

            let resolve = { (value: Any?) -> JSValue in
                let fn = ctx.objectForKeyedSubscript("__loomResolve")!
                return value.map { fn.call(withArguments: [$0])! } ?? fn.call(withArguments: [])!
            }
            let openBlock: @convention(block) (JSValue, JSValue, JSValue) -> JSValue = { _, _, _ in
                resolve(true)
            }
            let nextBlock: @convention(block) () -> JSValue = {
                resolve(queued.isEmpty ? nil : queued.removeFirst())
            }
            let respondBlock: @convention(block) (JSValue, JSValue, JSValue) -> Void = { idV, stV, bodyV in
                responses.append((Int(idV.toInt32()), Int(stV.toInt32()), bodyV.toString() ?? ""))
            }
            let closeBlock: @convention(block) () -> Void = { closed = true }

            if let factory = ctx.evaluateScript(serveJS),
               let web = factory.call(withArguments: [openBlock, nextBlock, respondBlock, closeBlock]) {
                ctx.setObject(web, forKeyedSubscript: "__web__" as NSString)
                ctx.evaluateScript("""
                var __done__ = false;
                __web__({
                  routes: {
                    '/sync':        function(){ return 'S'; },
                    '/async':       function(){ return Promise.resolve('A'); },
                    'POST /throws': function(){ throw new Error('boom <bad>'); }
                  }
                }).then(function(){ __done__ = true; });
                """)
                for _ in 0..<50 {
                    ctx.evaluateScript(";")
                    if ctx.evaluateScript("__done__")?.toBool() == true { break }
                }
            } else {
                failures.append("serve.factory")
            }

            check("serve.noException", exception == nil)
            check("serve.allResponded", responses.count == 4)
            check("serve.closed", closed)
            if responses.count == 4 {
                // Order preserved, and the loop kept going past the throwing route.
                check("serve.order", responses.map(\.id) == [1, 2, 3, 4])
                check("serve.sync", responses[0].status == 200 && responses[0].body == "S")
                // Proves `await fn(req)` really awaits — otherwise this is "[object Promise]".
                check("serve.asyncAwaited", responses[1].status == 200 && responses[1].body == "A")
                // Method-prefixed route matched, and the thrown message is escaped before display.
                check("serve.throwEscaped", responses[2].body.contains("&lt;bad&gt;"))
                check("serve.throwNoRaw", !responses[2].body.contains("<bad>"))
                check("serve.throwLogged", ctx.evaluateScript("__errors__.length")?.toInt32() == 1)
                check("serve.unmatched404", responses[3].status == 404)
            }
        } else {
            failures.append("serve.context")
        }

        if !failures.isEmpty {
            print("[LoomWebSheet.runSelfCheck] FAILED: \(failures.joined(separator: ", "))")
        }
        return failures.isEmpty
    }
}
#endif
