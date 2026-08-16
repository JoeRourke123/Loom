import Foundation
import JavaScriptCore

enum ModuleBundler {

    // MARK: - Public API

    /// A resolved non-entry module: already-compiled CJS plus the specifier→key mapping the
    /// runtime needs. `deps` is computed here, during the walk, so the JS side never re-derives
    /// a key — no path normalisation duplicated across two languages.
    struct Module {
        let cjs: String
        var deps: [String: String] = [:]
    }

    // MARK: - Public API

    /// Reads main.ts, compiles it, walks its import graph, and assembles a self-contained JSC
    /// payload. This is the whole I/O + graph half; `assemble` below is pure string joining.
    ///
    /// Throws on an unresolvable specifier, so a bad import is a compile error the Console shows
    /// rather than a `[Loom] Unknown module` thrown at script top level.
    static func bundle(project: LoomProject, session: RunSession? = nil) async throws -> String {
        let source = try String(contentsOf: project.mainFileURL, encoding: .utf8)
        let entryCJS = try await SWCCompiler.shared.compile(source)
        let modules = try await resolveModules(entryCJS: entryCJS, project: project, session: session)
        return assemble(entryCJS: entryCJS, modules: modules)
    }

    /// Single-file bundle with no import graph. Kept for runSelfCheck, which feeds hand-written
    /// CJS and has no project on disk to resolve against.
    static func bundle(compiledJS: String) -> String {
        assemble(entryCJS: compiledJS, modules: [:])
    }

    // MARK: - Assembly

    // @loom/widget is unconditionally included: ~35 lines of builder functions against ~3.8 MB
    // of vendor payloads, so gating it on whether the script imports it isn't worth the branch.
    //
    // The entry stays at top level rather than becoming a registry factory: executionFooter
    // reads module.exports off commonJSSetup's globals in three places, and making it a factory
    // would buy only the ability for the entry to take part in a cycle — which resolveLocal
    // deliberately forbids, since requiring the entry would execute it twice.
    private static func assemble(entryCJS: String, modules: [String: Module]) -> String {
        // Vendors imported by a helper count too — scanning only the entry would leave a helper's
        // `import _ from 'lodash'` with no IIFE in the payload and a throw at factory time.
        let scanned = ([entryCJS] + modules.values.map(\.cjs)).joined(separator: "\n")
        let requiredVendors = detectVendors(in: scanned)
        var parts: [String] = []

        parts.append(commonJSSetup)
        parts.append(loomCoreStub)
        parts.append(loomWidgetModule)

        var requireEntries: [String] = []
        for pkg in requiredVendors {
            if let iife = pkg.jsContent() {
                parts.append(iife)
                requireEntries.append("'\(pkg.rawValue)': \(pkg.globalName)")
            }
        }

        parts.append(requireShim(entries: requireEntries, modules: modules))
        parts.append(entryCJS)
        parts.append(executionFooter)

        return parts.joined(separator: "\n;\n")
    }


    // MARK: - Module resolution

    /// Breadth-first walk of the import graph, starting from the already-compiled entry.
    /// Returns registry key → module. Cycles terminate on the visited set; the runtime handles
    /// their semantics (see requireShim).
    /// A resolved import target. Local modules are files beside main.ts; remote ones are fetched
    /// URLs. The distinction also decides how *their* imports resolve — a remote module's
    /// siblings resolve against its URL, not against the project folder.
    private enum ModuleRef {
        case local(String)   // basename, already lowercased
        case remote(URL)

        var key: String {
            switch self {
            case .local(let name): return name
            case .remote(let url): return url.absoluteString
            }
        }
        var displayName: String {
            switch self {
            case .local(let name): return name + ".ts"
            case .remote(let url): return url.absoluteString
            }
        }
        var isRemote: Bool {
            if case .remote = self { return true }
            return false
        }
    }

    // A non-?bundle esm.sh URL can fan out into a graph of host-absolute re-exports. Runs have no
    // timeout, so an unbounded walk would just spin. 64 is far above any hand-written project and
    // well below "something has gone wrong".
    private static let moduleLimit = 64

    private static func resolveModules(
        entryCJS: String,
        project: LoomProject,
        session: RunSession?
    ) async throws -> [String: Module] {
        var modules: [String: Module] = [:]
        // Entry deps live under "" — the key the shim's top-level `require` passes as its base.
        var entryDeps: [String: String] = [:]
        var queue: [ModuleRef] = []

        for spec in moduleSpecifiers(in: entryCJS) {
            // Non-lenient, so this only ever returns nil-free values or throws.
            guard let ref = try resolve(spec, base: nil, project: project, importedBy: "main.ts") else { continue }
            entryDeps[spec] = ref.key
            queue.append(ref)
        }

        while let ref = queue.first {
            queue.removeFirst()
            if modules[ref.key] != nil { continue }
            guard modules.count < moduleLimit else {
                throw CompileError.moduleError("Import graph exceeded \(moduleLimit) modules — check for a runaway remote dependency")
            }

            let source = try await source(for: ref, project: project, session: session)

            // SWC reports line/column with no filename, so a helper's syntax error would
            // otherwise read as an error in main.ts.
            let cjs: String
            do {
                cjs = try await SWCCompiler.shared.compile(source)
            } catch {
                throw CompileError.moduleError("\(ref.displayName): \(error.localizedDescription)")
            }

            // Cached only now that it has compiled — otherwise one HTML error page gets stored
            // as .js and, since nothing is ever re-fetched automatically, stays broken forever.
            if case .remote(let url) = ref, RemoteModuleCache.cachedSource(for: url, project: project) == nil {
                RemoteModuleCache.store(source, for: url, project: project)
            }

            var module = Module(cjs: cjs)
            for spec in moduleSpecifiers(in: cjs) {
                // Remote payloads are third-party and may carry require() strings we can't
                // resolve; only user-authored files get a hard error for an unknown specifier.
                guard let resolved = try resolve(
                    spec, base: ref, project: project, importedBy: ref.displayName,
                    lenient: ref.isRemote
                ) else { continue }
                module.deps[spec] = resolved.key
                queue.append(resolved)
            }
            modules[ref.key] = module
        }

        if let session, !modules.isEmpty {
            let names = modules.keys.sorted().map { $0.contains("://") ? $0 : $0 + ".ts" }.joined(separator: ", ")
            session.append(LogEntry(
                runId: session.runId,
                projectName: project.name,
                level: .debug,
                message: "Bundled \(modules.count) module\(modules.count == 1 ? "" : "s"): \(names)",
                data: nil
            ))
        }

        modules[""] = Module(cjs: "", deps: entryDeps)
        return modules
    }

    /// Resolves one specifier against the module that imported it.
    ///
    /// `base` is nil for main.ts and `.local` for a helper — both resolve relative specifiers
    /// against the project folder. A `.remote` base resolves them against its own URL instead,
    /// which is what makes a non-`?bundle` esm.sh payload work: those emit host-absolute
    /// re-exports like `/date-fns@4.1.0/es2022/x.mjs`, and URL(string:relativeTo:) handles them.
    ///
    /// Returns nil only in lenient mode, used for third-party payloads that may contain
    /// require() strings we have no way to resolve.
    @discardableResult
    private static func resolve(
        _ specifier: String,
        base: ModuleRef?,
        project: LoomProject,
        importedBy: String,
        lenient: Bool = false
    ) throws -> ModuleRef? {
        if specifier.hasPrefix("http://") {
            throw CompileError.moduleError("\(importedBy): '\(specifier)' — remote modules must use https")
        }
        if specifier.hasPrefix("https://") {
            guard let url = URL(string: specifier) else {
                throw CompileError.moduleError("\(importedBy): '\(specifier)' is not a valid URL")
            }
            return try requireRemoteEnabled(url, importedBy: importedBy)
        }
        // A remote module's own imports are resolved relative to where it came from.
        if case .remote(let baseURL) = base {
            guard let url = URL(string: specifier, relativeTo: baseURL)?.absoluteURL else {
                if lenient { return nil }
                throw CompileError.moduleError("\(importedBy): could not resolve '\(specifier)'")
            }
            return try requireRemoteEnabled(url, importedBy: importedBy)
        }
        guard specifier.hasPrefix("./") || specifier.hasPrefix("../") else {
            if lenient { return nil }
            // Bare names reach here only after vendors and @loom/* have been filtered out.
            throw CompileError.moduleError("\(importedBy): '\(specifier)' is not an available package — use a relative path, an https URL, or one of the bundled vendor packages")
        }
        return .local(try resolveLocalName(specifier, project: project, importedBy: importedBy))
    }

    private static func requireRemoteEnabled(_ url: URL, importedBy: String) throws -> ModuleRef {
        guard remoteModulesEnabled else {
            throw CompileError.moduleError("\(importedBy): remote modules are turned off — enable them in Settings to import \(url.absoluteString)")
        }
        return .remote(url)
    }

    /// Default on. The toggle is a kill switch rather than a hurdle: it exists so a build can
    /// ship with remote modules disabled in one line, without unpicking the resolver.
    static var remoteModulesEnabled: Bool {
        UserDefaults.standard.object(forKey: "remoteModulesEnabled") as? Bool ?? true
    }

    /// Flat by design — no subfolders, no `../`. That matches what the app can actually create:
    /// the editor's file list is non-recursive and NewFileSheet rejects `/` in names.
    /// Mirrors the sanitiser shape used by AssistantTools.resolvedProjectFileURL.
    ///
    /// ponytail: flat resolution. If Loom.files-created subdirectories ever become visible in
    /// the editor, key the registry on the project-relative path instead of the basename.
    private static func resolveLocalName(_ specifier: String, project: LoomProject, importedBy: String) throws -> String {
        var name = specifier
        if name.hasPrefix("./") { name.removeFirst(2) }
        // Only ever strip a trailing ".ts" — never a generic pathExtension. That is what keeps
        // './secrets.json' unreachable: it resolves to a lookup for secrets.json.ts, which fails.
        if name.hasSuffix(".ts") { name.removeLast(3) }

        guard !name.isEmpty, !name.contains("/"), !name.hasPrefix(".") else {
            throw CompileError.moduleError("\(importedBy): '\(specifier)' — imports must name a file beside main.ts, with no folders")
        }
        // A specifier still carrying an editable extension after the .ts strip — './config.json',
        // './notes.md' — would otherwise resolve to a lookup for 'config.json.ts' and report that
        // the file wasn't found, which is nonsense when config.json is sitting right there.
        // Checked against the extension set rather than "contains a dot" so a legitimately dotted
        // name like './my.helpers' still falls through to normal resolution.
        let otherExtension = (name as NSString).pathExtension.lowercased()
        if !otherExtension.isEmpty, LoomProject.editableExtensions.contains(otherExtension) {
            throw CompileError.moduleError("\(importedBy): '\(specifier)' — only .ts files can be imported. Read data files at runtime with Loom.files.read() instead.")
        }
        // Requiring the entry would execute it a second time: loom() called twice, every
        // top-level side effect repeated. Reject it by name rather than letting it reach the runtime.
        guard name.lowercased() != "main" else {
            throw CompileError.moduleError("\(importedBy): cannot import './main' — it is already the entry point")
        }

        let url = project.folderURL.appendingPathComponent(name + ".ts")
        // Compared as paths, not URLs. deletingLastPathComponent() always yields a trailing slash,
        // so URL equality only held because both LoomProject construction sites happen to come from
        // contentsOfDirectory(at:), which marks directories as such. A folderURL built by hand with
        // appendingPathComponent has no trailing slash, and every sibling import then failed with
        // "not found" while the file sat right there. .path normalizes both sides.
        guard url.standardizedFileURL.deletingLastPathComponent().path == project.folderURL.standardizedFileURL.path,
              FileManager.default.fileExists(atPath: url.path) else {
            throw CompileError.moduleError("\(importedBy): '\(specifier)' not found — expected \(name).ts beside main.ts")
        }
        // Lowercased because iOS containers are case-insensitive: './Helpers' and './helpers'
        // open the same file and must not become two factories with two copies of module state.
        // The file lookup above uses the specifier as written, so case-sensitive volumes still work.
        return name.lowercased()
    }

    /// Everything the walk has to resolve: vendors and @loom/* keep the existing fast path in
    /// the require map and are filtered out here.
    private static func moduleSpecifiers(in js: String) -> [String] {
        requireSpecifiers(in: js).filter {
            !$0.hasPrefix("@loom/") && VendorPackage.package(for: $0) == nil
        }
    }

    /// Reads a module's source: from disk for local files, from the per-project cache or the
    /// network for remote ones.
    private static func source(for ref: ModuleRef, project: LoomProject, session: RunSession?) async throws -> String {
        switch ref {
        case .local(let name):
            let url = project.folderURL.appendingPathComponent(name + ".ts")
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                throw CompileError.moduleError("\(name).ts: could not be read")
            }
            return text

        case .remote(let url):
            if let cached = RemoteModuleCache.cachedSource(for: url, project: project) { return cached }
            // Logged so a network fetch is never invisible — the run record should say what was
            // downloaded and executed.
            session?.append(LogEntry(
                runId: session!.runId, projectName: project.name, level: .info,
                message: "Fetching \(url.absoluteString)", data: nil
            ))
            do {
                return try await RemoteModuleCache.fetch(url)
            } catch let error as CompileError {
                throw error
            } catch {
                throw CompileError.moduleError("\(url.absoluteString): \(error.localizedDescription)")
            }
        }
    }

    private static func requireSpecifiers(in js: String) -> [String] {
        let pattern = #"require\(['"]([^'"]+)['"]\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(js.startIndex..., in: js)
        return regex.matches(in: js, range: range).compactMap { match -> String? in
            guard let r = Range(match.range(at: 1), in: js) else { return nil }
            return String(js[r])
        }
    }

    // Stays a scan, never a trust decision: a remote payload with the literal require("lodash")
    // inside a string would pull in the vendor IIFE. Harmless, and cheaper than parsing.
    private static func detectVendors(in js: String) -> [VendorPackage] {
        Array(Set(requireSpecifiers(in: js)).compactMap { VendorPackage.package(for: $0) })
    }

    // MARK: - JS Templates

    private static let commonJSSetup = """
    var module = { exports: {} };
    var exports = module.exports;
    """

    // __loom_esc__ lives here rather than in LoomBridge's preamble so it travels with the bundle:
    // runSelfCheck() exercises the html tag in a bare JSContext with no bridge injected. The
    // Loom.ui.web serve loop also calls it, and that's safe — the loop is only ever *invoked*
    // from user script code, which by definition runs after this stub has been evaluated.
    static let loomCoreStub = """
    var __loom_esc__ = function(v) {
      if (v === null || v === undefined) return '';
      return String(v)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
    };
    var __loom_config__ = null;
    var __loom_core__ = {
      loom: function(handler, config) {
        if (config) __loom_config__ = config;
        return handler;
      },
      // Tagged template for HTML. Interpolations are escaped by default — that default IS the
      // security control for Loom.ui.web(), where a fetched RSS title or API response would
      // otherwise execute as <script> in the loomweb://app origin. Nested html`` fragments and
      // arrays of them carry __html and pass through unescaped, so composing doesn't double-escape.
      html: function(strings) {
        var out = strings[0];
        for (var i = 1; i < arguments.length; i++) {
          var v = arguments[i];
          if (Array.isArray(v)) {
            v = v.map(function(x) { return (x && x.__html !== undefined) ? x.__html : __loom_esc__(x); }).join('');
          } else if (v && v.__html !== undefined) {
            v = v.__html;
          } else {
            v = __loom_esc__(v);
          }
          out += v + strings[i];
        }
        return { __html: out, toString: function() { return out; } };
      }
    };
    """

    // @loom/widget module — 22 w.* builder functions as a self-contained IIFE.
    // Assigns to globalThis.__loom_widget__ which the requireShim maps to '@loom/widget'.
    private static let loomWidgetModule = """
    (function() {
      'use strict';
      function n(type, props, children) {
        var obj = { type: type, props: props || {} };
        if (children !== undefined) obj.children = children;
        return obj;
      }
      var w = {
        vstack:      function(c, p) { return n('vstack', p, c); },
        hstack:      function(c, p) { return n('hstack', p, c); },
        zstack:      function(c, p) { return n('zstack', p, c); },
        spacer:      function(p)    { return n('spacer', p); },
        divider:     function(p)    { return n('divider', p); },
        text:        function(x, p) { if (x && typeof x === 'object') return n('text', x); return n('text', Object.assign({ content: String(x) }, p || {})); },
        label:       function(p)    { return n('label', p); },
        image:       function(u, p) { if (u && typeof u === 'object') return n('image', u); return n('image', Object.assign({ url: String(u) }, p || {})); },
        icon:        function(x, p) { if (x && typeof x === 'object') return n('icon', x); return n('icon', Object.assign({ name: String(x) }, p || {})); },
        link:        function(p)    { return n('link', p); },
        ring:        function(p)    { return n('ring', p); },
        gauge:       function(p)    { return n('gauge', p); },
        lineChart:   function(p)    { return n('lineChart', p); },
        barChart:    function(p)    { return n('barChart', p); },
        sparkline:   function(p)    { return n('sparkline', p); },
        progressBar: function(p)    { return n('progressBar', p); },
        rectangle:   function(c, p) { return n('rectangle', p, c); },
        capsule:     function(c, p) { return n('capsule', p, c); },
        circle:      function(c, p) { return n('circle', p, c); },
        gradient:    function(p)    { return n('gradient', p); },
        button:      function(p)    { return n('button', p); },
        toggle:      function(p)    { return n('toggle', p); }
      };
      globalThis.__loom_widget__ = { w: w };
    })();
    """

    private static func requireShim(entries: [String], modules: [String: Module]) -> String {
        let allEntries = ["'@loom/widget': __loom_widget__"] + entries
        let vendorMap = allEntries.joined(separator: ",\n  ")

        // Sorted so the payload is byte-stable across runs — dictionary order would make
        // self-check failures intermittent.
        let registry = modules.keys.sorted().map { key -> String in
            let module = modules[key]!
            let deps = module.deps.keys.sorted()
                .map { "'\($0)': '\(module.deps[$0]!)'" }
                .joined(separator: ", ")
            // The entry has no factory: it runs at top level, and only its deps map is needed
            // so that its own require() calls can resolve.
            let fn = key.isEmpty ? "null" : """
            function (module, exports, require) {
            \(module.cjs)
            }
            """
            return """
              '\(key)': { deps: { \(deps) }, fn: \(fn) }
            """
        }.joined(separator: ",\n")

        return """
        var __loom_require_map__ = Object.assign(Object.create(null), {
          '@loom/core': __loom_core__,
          \(vendorMap)
        });

        // Local modules, keyed by resolved id. Nothing here runs until something requires it.
        // `deps` maps a specifier exactly as it appears in that module's require() calls to the
        // registry key Swift resolved it to while walking the graph, so the runtime never has to
        // re-derive a key.
        var __loom_modules__ = Object.assign(Object.create(null), {
        \(registry)
        });

        var __loom_cache__ = Object.create(null);

        // Object.create(null) throughout: a plain object literal would resolve require('toString')
        // through the prototype chain and hand back Object.prototype.toString.
        function __loom_require__(id, base) {
          var owner = __loom_modules__[base];
          var key = (owner && owner.deps[id]) || id;
          if (key in __loom_require_map__) return __loom_require_map__[key];
          if (key in __loom_cache__) return __loom_cache__[key].exports;
          var target = __loom_modules__[key];
          if (target && target.fn) {
            var m = { exports: {} };
            // Cached before executing, so an import cycle sees a partially-filled exports object
            // rather than recursing forever — same rule as Node's CJS loader.
            __loom_cache__[key] = m;
            target.fn(m, m.exports, function (i) { return __loom_require__(i, key); });
            return m.exports;
          }
          throw new Error('[Loom] Unknown module: ' + id);
        }

        function require(id) { return __loom_require__(id, ''); }
        """
    }

    private static let executionFooter = """
    (function() {
      var __fn__ = (module.exports && module.exports.default) ? module.exports.default : module.exports;
      if (typeof __fn__ !== 'function') {
        __loom_error__ = 'Script default export is not a function';
        return;
      }
      Promise.resolve(__fn__(ctx))
        .then(function(r) {
          var resultJSON;
          try { resultJSON = JSON.stringify(r !== undefined ? r : null); }
          catch(e) { resultJSON = 'null'; }
          // __loom_result__ is set only once entity AND widget collection below have fully
          // settled — the drain loop in ScriptRunner.execute() exits as soon as __loom_result__
          // is defined, so this ordering (rather than separate completion flags) is what
          // guarantees __loom_entities_result__ / __loom_widget_result__ are already populated
          // by the time Swift reads them.
          return __loom_collect_entities__()
            .then(function() { return __loom_collect_widget__(r); })
            .then(function() { __loom_result__ = resultJSON; });
        })
        .catch(function(e) {
          __loom_error__ = e && e.message ? e.message : String(e);
        });
    })();

    // Runs only after the main handler resolves (never on error). For each entities.<type>
    // declared in the static config, calls its named `provider` export (no args) and collects
    // the results — providers commonly read from Loom.db/Loom.kv, so this chains Promises
    // rather than assuming a sync return. One provider throwing doesn't block the others.
    function __loom_collect_entities__() {
      var entities = __loom_config__ && __loom_config__.entities;
      if (!entities || typeof entities !== 'object') return Promise.resolve();

      var out = {};
      var chain = Promise.resolve();
      Object.keys(entities).forEach(function(typeName) {
        chain = chain.then(function() {
          var spec = entities[typeName];
          var fn = spec && spec.provider && module.exports ? module.exports[spec.provider] : null;
          if (typeof fn !== 'function') return;
          // fn() is called inside the chain, not as an argument to Promise.resolve — otherwise a
          // provider that throws synchronously throws before Promise.resolve is ever reached,
          // escapes the catch below, and takes down the whole run.
          return Promise.resolve().then(function() { return fn(); })
            .then(function(records) { out[typeName] = records; })
            .catch(function() { /* one provider failing shouldn't block others */ });
        });
      });
      return chain.then(function() {
        try { __loom_entities_result__ = JSON.stringify(out); } catch (e) { /* leave unset */ }
      });
    }

    // Runs only after the main handler resolves. Calls the `widget` named export once with the
    // handler's return value as ctx.data — unlike the old widget.ts runner this shares the main
    // JSContext, so it has the full Loom bridge and may be async.
    //
    // One call, not one per family: returning a w.* node reuses it for every size, returning a
    // { small, medium, large, extraLarge } map gives per-family trees. A node always carries
    // `.type` and a size map never does, which is what tells the two apart.
    //
    // A throwing widget is reported via __loom_widget_error__ but never rejects — a broken
    // widget must not fail an otherwise-successful run.
    function __loom_collect_widget__(data) {
      var fn = module.exports ? module.exports.widget : null;
      if (typeof fn !== 'function') return Promise.resolve();

      var widgetCtx = {
        input: ctx.input,
        data: data !== undefined ? data : null,
        trigger: 'widgetRender',
        runId: ctx.runId
      };

      // Called inside the chain rather than as an argument to Promise.resolve: a widget that
      // throws synchronously would otherwise throw before Promise.resolve runs, escape the catch
      // below, and fail the whole run — which is exactly what this collector exists to prevent.
      return Promise.resolve().then(function() { return fn(widgetCtx); })
        .then(function(tree) {
          if (!tree || typeof tree !== 'object') return;
          var cfg = __loom_config__ && __loom_config__.widget;
          var out = {
            refreshAfter: (cfg && typeof cfg.refreshAfter === 'number') ? cfg.refreshAfter : null,
            runOnTap: !!(cfg && cfg.runOnTap === true)
          };
          var sizes = ['small', 'medium', 'large', 'extraLarge'];
          var isNode = typeof tree.type === 'string';
          for (var i = 0; i < sizes.length; i++) {
            out[sizes[i]] = isNode ? tree : (tree[sizes[i]] || null);
          }
          __loom_widget_result__ = JSON.stringify(out);
        })
        .catch(function(e) {
          __loom_widget_error__ = e && e.message ? e.message : String(e);
        });
    }
    """

    // MARK: - Self-check

    // Regression guard on the core execution footer, used by every script run — exercises the
    // real bundle() + JS footer end-to-end (not a mock), both with and without an entities
    // config, so a change here can't silently break the plain-script path everything else
    // depends on. No test target exists in this project; callable directly instead of XCTest.
    #if DEBUG
    @discardableResult
    static func runSelfCheck() -> Bool {
        var failures: [String] = []
        func check(_ name: String, _ condition: @autoclosure () -> Bool) {
            if !condition() { failures.append(name) }
        }

        struct Outcome {
            var result: String?
            var error: String?
            var entities: String?
            var widget: String?
            var widgetError: String?
        }

        func runAssembled(_ bundled: String) -> Outcome {
            guard let vm = JSVirtualMachine(), let ctx = JSContext(virtualMachine: vm) else {
                return Outcome(error: "failed to create JSContext")
            }
            var exception: String? = nil
            ctx.exceptionHandler = { _, ex in exception = ex?.toString() }

            ctx.evaluateScript("var ctx = { input: {}, trigger: 'manual', runId: 'selfcheck' };")
            ctx.evaluateScript("var __loom_result__ = undefined; var __loom_error__ = undefined; var __loom_entities_result__ = undefined; var __loom_widget_result__ = undefined; var __loom_widget_error__ = undefined;")
            ctx.evaluateScript(bundled)

            for _ in 0..<20 {
                ctx.evaluateScript(";")
                let done = ctx.evaluateScript("typeof __loom_result__ !== 'undefined' || typeof __loom_error__ !== 'undefined'")?.toBool() == true
                if done { break }
            }

            func read(_ name: String) -> String? {
                guard let v = ctx.evaluateScript(name), !v.isUndefined else { return nil }
                return v.toString()
            }
            return Outcome(
                result: read("__loom_result__"),
                error: read("__loom_error__") ?? exception,
                entities: read("__loom_entities_result__"),
                widget: read("__loom_widget_result__"),
                widgetError: read("__loom_widget_error__")
            )
        }

        func runBundled(_ compiledJS: String) -> Outcome {
            runAssembled(bundle(compiledJS: compiledJS))
        }

        // No entities declared — must behave exactly as before entity collection was added.
        let plain = runBundled("""
        var _core = require('@loom/core');
        module.exports.default = _core.loom(async (ctx) => {
          return { greeting: 'hi' };
        }, {
          name: 'Test',
          description: 'x',
        });
        """)
        check("plain.result", plain.result == "{\"greeting\":\"hi\"}")
        check("plain.noError", plain.error == nil)
        check("plain.noEntities", plain.entities == nil)
        check("plain.noWidget", plain.widget == nil)

        // html tagged template. Escaping by default is the security control for Loom.ui.web(),
        // so these are the assertions that must never regress.
        let htmlTag = runBundled("""
        var _core = require('@loom/core');
        var html = _core.html;
        module.exports.default = _core.loom(async (ctx) => {
          return {
            esc:    String(html`<p>${'<script>alert(1)</script>'}</p>`),
            nested: String(html`<ul>${[html`<li>a</li>`, html`<li>b</li>`]}</ul>`),
            amp:    String(html`<i>${'a & b'}</i>`),
            empty:  String(html`<b>${null}${undefined}</b>`),
          };
        }, {
          name: 'Test',
          description: 'x',
        });
        """)
        check("html.noError", htmlTag.error == nil)
        check("html.escapes", htmlTag.result?.contains("&lt;script&gt;alert(1)&lt;/script&gt;") == true)
        check("html.noRawScript", htmlTag.result?.contains("<script>") == false)
        // Nested fragments and arrays of them compose without double-escaping or separators.
        check("html.nested", htmlTag.result?.contains("<ul><li>a</li><li>b</li></ul>") == true)
        // & must be replaced first, else this reads "a &amp;amp; b".
        check("html.ampersandFirst", htmlTag.result?.contains("a &amp; b") == true)
        check("html.nullish", htmlTag.result?.contains("<b></b>") == true)

        // Entities declared — provider export runs and results are collected.
        let withEntities = runBundled("""
        var _core = require('@loom/core');
        module.exports.noteProvider = function() {
          return [{ id: 'n1', title: 'Note One' }, { id: 'n2', title: 'Note Two' }];
        };
        module.exports.default = _core.loom(async (ctx) => {
          return { ok: true };
        }, {
          name: 'Test',
          description: 'x',
          entities: {
            note: { displayName: 'Note', fields: { title: { type: 'string' } }, provider: 'noteProvider' }
          },
        });
        """)
        check("entities.result", withEntities.result == "{\"ok\":true}")
        check("entities.noError", withEntities.error == nil)
        check("entities.hasRecord1", withEntities.entities?.contains("Note One") == true)
        check("entities.hasRecord2", withEntities.entities?.contains("n2") == true)

        // A bare node return is reused for every family, and receives the handler's result as
        // ctx.data.
        let widgetNode = runBundled("""
        var _core = require('@loom/core');
        var w = require('@loom/widget').w;
        module.exports.widget = function (ctx) {
          return w.text(ctx.data.city);
        };
        module.exports.default = _core.loom(async (ctx) => {
          return { city: 'London' };
        }, {
          name: 'Test',
          description: 'x',
          widget: { refreshAfter: 900 },
        });
        """)
        check("widgetNode.result", widgetNode.result == "{\"city\":\"London\"}")
        check("widgetNode.noError", widgetNode.error == nil)
        check("widgetNode.noWidgetError", widgetNode.widgetError == nil)
        check("widgetNode.refreshAfter", widgetNode.widget?.contains("\"refreshAfter\":900") == true)
        check("widgetNode.allSizes", ["small", "medium", "large", "extraLarge"].allSatisfy {
            widgetNode.widget?.contains("\"\($0)\":{\"type\":\"text\",\"props\":{\"content\":\"London\"}}") == true
        })

        // A size map fans out per family; omitted keys serialise as null rather than repeating
        // the node. Also covers the async form, which the old widget.ts runner couldn't support.
        let widgetMap = runBundled("""
        var _core = require('@loom/core');
        var w = require('@loom/widget').w;
        module.exports.widget = async (ctx) => ({
          small: w.text('S'),
          large: w.text('L'),
        });
        module.exports.default = _core.loom(async (ctx) => {
          return { ok: true };
        }, {
          name: 'Test',
          description: 'x',
        });
        """)
        check("widgetMap.result", widgetMap.result == "{\"ok\":true}")
        check("widgetMap.small", widgetMap.widget?.contains("\"small\":{\"type\":\"text\",\"props\":{\"content\":\"S\"}}") == true)
        check("widgetMap.large", widgetMap.widget?.contains("\"large\":{\"type\":\"text\",\"props\":{\"content\":\"L\"}}") == true)
        check("widgetMap.mediumNull", widgetMap.widget?.contains("\"medium\":null") == true)
        check("widgetMap.noRefreshAfter", widgetMap.widget?.contains("\"refreshAfter\":null") == true)

        // A throwing widget must not take the run down with it — the handler's result still
        // lands, the failure is reported separately.
        let widgetThrows = runBundled("""
        var _core = require('@loom/core');
        module.exports.widget = (ctx) => { throw new Error('boom'); };
        module.exports.default = _core.loom(async (ctx) => {
          return { ok: true };
        }, {
          name: 'Test',
          description: 'x',
        });
        """)
        check("widgetThrows.result", widgetThrows.result == "{\"ok\":true}")
        check("widgetThrows.runNotFailed", widgetThrows.error == nil)
        check("widgetThrows.reported", widgetThrows.widgetError == "boom")
        check("widgetThrows.noWidget", widgetThrows.widget == nil)

        // ── Module registry ──────────────────────────────────────────────────────────────────
        // assemble() is driven directly with hand-built modules, so these exercise the emitted
        // require()/cache/deps runtime without needing a project on disk. Swift-side resolution
        // (resolveLocal) is covered by the manual two-file check in the plan.
        func entry(_ body: String, deps: [String: String] = [:]) -> String {
            """
            var _core = require('@loom/core');
            module.exports.default = _core.loom(async (ctx) => { \(body) }, { name: 'T', description: 'x' });
            """
        }
        func runModules(_ entryCJS: String, _ modules: [String: Module]) -> Outcome {
            runAssembled(assemble(entryCJS: entryCJS, modules: modules))
        }

        // A named export crosses the module boundary.
        let imported = runModules(
            entry("return { v: require('./helpers').label() };", deps: [:]),
            [
                "": Module(cjs: "", deps: ["./helpers": "helpers"]),
                "helpers": Module(cjs: "module.exports.label = function () { return 'from-helper'; };"),
            ]
        )
        check("import.noError", imported.error == nil)
        check("import.result", imported.result == "{\"v\":\"from-helper\"}")

        // A module required twice is instantiated once — the cache is what makes module-level
        // state shared rather than duplicated.
        let once = runModules(
            entry("var a = require('./counter'); var b = require('./counter'); return { n: a.bump(), m: b.bump() };"),
            [
                "": Module(cjs: "", deps: ["./counter": "counter"]),
                "counter": Module(cjs: "var n = 0; module.exports.bump = function () { return ++n; };"),
            ]
        )
        check("once.result", once.result == "{\"n\":1,\"m\":2}")

        // A cycle must terminate. Function exports survive it because they hoist; this is the
        // guarantee documented for cycles, and cache-before-execute is what provides it.
        let cycle = runModules(
            entry("return { v: require('./a').go() };"),
            [
                "": Module(cjs: "", deps: ["./a": "a"]),
                "a": Module(cjs: "var b = require('./b'); module.exports.go = function () { return 'a' + b.tail(); };",
                            deps: ["./b": "b"]),
                "b": Module(cjs: "var a = require('./a'); module.exports.tail = function () { return 'b'; };",
                            deps: ["./a": "a"]),
            ]
        )
        check("cycle.noError", cycle.error == nil)
        check("cycle.result", cycle.result == "{\"v\":\"ab\"}")

        // @loom/core resolves from inside a factory, not just at top level.
        let coreFromHelper = runModules(
            entry("return { v: require('./h').tag() };"),
            [
                "": Module(cjs: "", deps: ["./h": "h"]),
                "h": Module(cjs: "var c = require('@loom/core'); module.exports.tag = function () { return String(c.html`<i>${'x'}</i>`); };"),
            ]
        )
        check("coreFromHelper.result", coreFromHelper.result?.contains("<i>x</i>") == true)

        // A vendor imported only by a helper must still get its IIFE into the payload —
        // scanning just the entry would miss it and the require would throw at factory time.
        let helperVendor = assemble(
            entryCJS: entry("return {};"),
            modules: [
                "": Module(cjs: "", deps: ["./h": "h"]),
                "h": Module(cjs: "var _ = require('lodash'); module.exports.sum = function () { return _.sum([1,2]); };"),
            ]
        )
        check("helperVendor.iifeIncluded", helperVendor.contains(VendorPackage.lodash.globalName))

        // Unknown specifiers throw rather than resolving to something surprising. 'toString'
        // would previously have come back off Object.prototype through the require map.
        let unknown = runModules(entry("try { require('./nope'); return { t: 'no-throw' }; } catch (e) { return { t: 'threw' }; }"), [:])
        check("unknown.throws", unknown.result == "{\"t\":\"threw\"}")
        let proto = runModules(entry("try { require('toString'); return { t: 'no-throw' }; } catch (e) { return { t: 'threw' }; }"), [:])
        check("proto.throws", proto.result == "{\"t\":\"threw\"}")

        if failures.isEmpty {
            print("[ModuleBundler] self-check passed")
        } else {
            print("[ModuleBundler] self-check FAILED: \(failures.joined(separator: ", "))")
        }
        return failures.isEmpty
    }

    // The only automated guard on the SWC swap: runSelfCheck above feeds hand-written CJS
    // straight to bundle(), so nothing there would notice if the compiler stopped emitting the
    // shape the footer expects. This runs a real script through the real compiler. Async, hence
    // separate — LoomApp.init() can't await.
    @discardableResult
    static func runCompilerSelfCheck() async -> Bool {
        var failures: [String] = []
        func check(_ name: String, _ condition: @autoclosure () -> Bool) {
            if !condition() { failures.append(name) }
        }

        let source = """
        import { loom } from '@loom/core';
        export class Helper { label(): string { return 'ok'; } }
        export const provider = async () => [{ id: '1' }];
        export default loom(async (ctx) => {
          const value: number = 41;
          return { n: value + 1, label: new Helper().label() };
        }, { name: 'CompilerCheck', description: 'x' });
        """

        let compiled: String
        do {
            compiled = try await SWCCompiler.shared.compile(source)
        } catch {
            print("[ModuleBundler] compiler self-check FAILED: \(error.localizedDescription)")
            return false
        }

        // Helpers must be inlined. externalHelpers:true would emit
        // require("@swc/helpers/…"), which the require shim cannot resolve — and it fails at
        // script runtime, not compile time, so this string is the tripwire for the whole class.
        check("noExternalHelpers", !compiled.contains("@swc/helpers"))
        check("emitsCJS", compiled.contains("require(\"@loom/core\")"))
        check("stripsTypes", !compiled.contains(": string"))

        let bundled = bundle(compiledJS: compiled)
        guard let vm = JSVirtualMachine(), let ctx = JSContext(virtualMachine: vm) else { return false }
        var exception: String?
        ctx.exceptionHandler = { _, ex in exception = ex?.toString() }
        ctx.evaluateScript("var ctx = { input: {}, trigger: 'manual', runId: 'selfcheck' };")
        ctx.evaluateScript("var __loom_result__ = undefined; var __loom_error__ = undefined; var __loom_entities_result__ = undefined; var __loom_widget_result__ = undefined; var __loom_widget_error__ = undefined;")
        ctx.evaluateScript(bundled)
        for _ in 0..<20 {
            ctx.evaluateScript(";")
            if ctx.evaluateScript("typeof __loom_result__ !== 'undefined' || typeof __loom_error__ !== 'undefined'")?.toBool() == true { break }
        }

        // The footer reads module.exports.default off SWC's accessor-backed exports object.
        // If that ever stops resolving, every script run breaks at once.
        let result = ctx.evaluateScript("__loom_result__")
        check("noException", exception == nil)
        check("footerFoundDefault", result?.isUndefined == false)
        check("result", result?.toString() == "{\"n\":42,\"label\":\"ok\"}")

        if failures.isEmpty {
            print("[ModuleBundler] compiler self-check passed")
        } else {
            print("[ModuleBundler] compiler self-check FAILED: \(failures.joined(separator: ", "))")
        }
        return failures.isEmpty
    }
    #endif
}
