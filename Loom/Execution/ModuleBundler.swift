import Foundation
import JavaScriptCore

enum ModuleBundler {

    // MARK: - Public API

    // Bundles a main.ts SWC-compiled ESM string into a self-contained JSC payload.
    // collectExports: true so an entity `provider` named export (e.g. `export function
    // recipeProvider() {...}`) actually lands on module.exports — the entity-collection pass
    // in executionFooter looks it up there after the main handler succeeds.
    static func bundle(compiledJS: String) -> String {
        let cjsScript = esmToCJS(compiledJS, collectExports: true).script
        let requiredVendors = detectVendors(in: cjsScript)
        var parts: [String] = []

        parts.append(commonJSSetup)
        parts.append(loomCoreStub)

        var requireEntries: [String] = []
        for pkg in requiredVendors {
            if let iife = pkg.jsContent() {
                parts.append(iife)
                requireEntries.append("'\(pkg.rawValue)': \(pkg.globalName)")
            }
        }

        parts.append(requireShim(entries: requireEntries, includeWidget: false))
        parts.append(cjsScript)
        parts.append(executionFooter)

        return parts.joined(separator: "\n;\n")
    }

    // Bundles a widget.ts SWC-compiled ESM string. Includes the @loom/widget module and
    // uses widgetExecutionFooter which calls each named size export as a factory.
    static func widgetBundle(compiledJS: String) -> String {
        let (cjsScript, _) = esmToCJS(compiledJS, collectExports: true)
        let requiredVendors = detectVendors(in: cjsScript)
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

        parts.append(requireShim(entries: requireEntries, includeWidget: true))
        parts.append(cjsScript)
        parts.append(widgetExecutionFooter)

        return parts.joined(separator: "\n;\n")
    }

    // MARK: - ESM → CJS Conversion

    // Returns the converted script plus a list of collected named export identifiers.
    // When collectExports is true, export const/let/var and export { } are emitted as
    // module.exports assignments so the widget footer can call each size factory.
    private static func esmToCJS(_ esm: String, collectExports: Bool) -> (script: String, exports: [String]) {
        var counter = 0
        var output: [String] = []
        var namedExports: [String] = []

        for line in esm.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // import * as NS from 'pkg'
            if let m = capture(trimmed, pattern: #"^import\s+\*\s+as\s+(\w+)\s+from\s+['"]([^'"]+)['"]"#) {
                output.append("var \(m[1]) = require('\(m[2])');")
                continue
            }

            // import Default, { named } from 'pkg'
            if let m = capture(trimmed, pattern: #"^import\s+(\w+)\s*,\s*\{([^}]+)\}\s+from\s+['"]([^'"]+)['"]"#) {
                let tmp = "__loom_imp_\(counter)__"; counter += 1
                output.append("var \(tmp) = require('\(m[3])');")
                output.append("var \(m[1]) = \(tmp).default || \(tmp);")
                for name in splitNames(m[2]) { output.append(namedImport(name, from: tmp)) }
                continue
            }

            // import { named } from 'pkg'
            if let m = capture(trimmed, pattern: #"^import\s+\{([^}]+)\}\s+from\s+['"]([^'"]+)['"]"#) {
                let tmp = "__loom_imp_\(counter)__"; counter += 1
                output.append("var \(tmp) = require('\(m[2])');")
                for name in splitNames(m[1]) { output.append(namedImport(name, from: tmp)) }
                continue
            }

            // import Default from 'pkg'
            if let m = capture(trimmed, pattern: #"^import\s+(\w+)\s+from\s+['"]([^'"]+)['"]"#) {
                let tmp = "__loom_imp_\(counter)__"; counter += 1
                output.append("var \(tmp) = require('\(m[2])');")
                output.append("var \(m[1]) = \(tmp).default || \(tmp);")
                continue
            }

            // import 'pkg' — side-effect only
            if capture(trimmed, pattern: #"^import\s+['"][^'"]+['"]"#) != nil {
                continue
            }

            // export default <expr>
            if trimmed.hasPrefix("export default ") {
                output.append("module.exports.default = " + trimmed.dropFirst("export default ".count))
                continue
            }

            // export const/let/var foo = <expr>
            // Strip "export " prefix, keep the declaration; defer module.exports assignment to end.
            if let m = capture(trimmed, pattern: #"^export\s+(const|let|var)\s+(\w+)\b"#) {
                // Find where the keyword starts and emit from there
                if let re = try? NSRegularExpression(pattern: #"^export\s+"#),
                   let match = re.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
                   let range = Range(match.range, in: trimmed) {
                    output.append(String(trimmed[range.upperBound...]))
                } else {
                    output.append(trimmed)
                }
                if collectExports { namedExports.append(m[2]) }
                continue
            }

            // export { a, b } or export { a as b }
            if let m = capture(trimmed, pattern: #"^export\s+\{([^}]+)\}"#) {
                if collectExports {
                    for name in splitNames(m[1]) {
                        if let alias = capture(name, pattern: #"(\w+)\s+as\s+(\w+)"#) {
                            output.append("module.exports.\(alias[2]) = \(alias[1]);")
                        } else {
                            let trimmedName = name.trimmingCharacters(in: .whitespaces)
                            output.append("module.exports.\(trimmedName) = \(trimmedName);")
                        }
                    }
                }
                continue
            }

            output.append(line)
        }

        // Emit module.exports for collected named exports (export const/let/var)
        if collectExports {
            for name in namedExports {
                output.append("module.exports.\(name) = \(name);")
            }
        }

        return (output.joined(separator: "\n"), namedExports)
    }

    // MARK: - Helpers

    private static func capture(_ s: String, pattern: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s))
        else { return nil }
        return (0..<m.numberOfRanges).map { i in
            guard let r = Range(m.range(at: i), in: s) else { return "" }
            return String(s[r])
        }
    }

    private static func splitNames(_ s: String) -> [String] {
        s.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private static func namedImport(_ name: String, from tmp: String) -> String {
        if let m = capture(name, pattern: #"(\w+)\s+as\s+(\w+)"#) {
            return "var \(m[2]) = \(tmp).\(m[1]);"
        }
        return "var \(name) = \(tmp).\(name);"
    }

    private static func detectVendors(in js: String) -> [VendorPackage] {
        let pattern = #"require\(['"]([^'"]+)['"]\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(js.startIndex..., in: js)
        let matches = regex.matches(in: js, range: range)
        let names = matches.compactMap { match -> String? in
            guard let r = Range(match.range(at: 1), in: js) else { return nil }
            return String(js[r])
        }
        return Array(Set(names).compactMap { VendorPackage.package(for: $0) })
    }

    // MARK: - JS Templates

    private static let commonJSSetup = """
    var module = { exports: {} };
    var exports = module.exports;
    """

    private static let loomCoreStub = """
    var __loom_config__ = null;
    var __loom_core__ = {
      loom: function(handler, config) {
        if (config) __loom_config__ = config;
        return handler;
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

    private static func requireShim(entries: [String], includeWidget: Bool) -> String {
        var allEntries = entries
        if includeWidget {
            allEntries.insert("'@loom/widget': __loom_widget__", at: 0)
        }
        let vendorMap = allEntries.isEmpty ? "" : allEntries.joined(separator: ",\n  ")
        return """
        var __loom_require_map__ = {
          '@loom/core': __loom_core__,
          \(vendorMap)
        };
        function require(id) {
          if (id in __loom_require_map__) return __loom_require_map__[id];
          throw new Error('[Loom] Unknown module: ' + id);
        }
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
          // __loom_result__ is set only once entity collection below has fully settled — the
          // drain loop in ScriptRunner.execute() exits as soon as __loom_result__ is defined,
          // so this ordering (rather than a separate completion flag) is what guarantees
          // __loom_entities_result__ is already populated by the time Swift reads it.
          return __loom_collect_entities__().then(function() {
            __loom_result__ = resultJSON;
          });
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
          return Promise.resolve(fn())
            .then(function(records) { out[typeName] = records; })
            .catch(function() { /* one provider failing shouldn't block others */ });
        });
      });
      return chain.then(function() {
        try { __loom_entities_result__ = JSON.stringify(out); } catch (e) { /* leave unset */ }
      });
    }
    """

    // Calls each named size export (small/medium/large/extraLarge) as a factory function
    // with its own ctx (matching widgetSize), collects the component trees, and assigns
    // the serialised result to __loom_widget_result__.
    private static let widgetExecutionFooter = """
    (function() {
      var __sizes__ = ['small', 'medium', 'large', 'extraLarge'];
      var __result__ = {};
      __result__.refreshAfter = (__loom_config__ && __loom_config__.refreshAfter) ? __loom_config__.refreshAfter : null;
      for (var i = 0; i < __sizes__.length; i++) {
        var size = __sizes__[i];
        var fn = module.exports[size];
        if (typeof fn === 'function') {
          try {
            var sizeCtx = { input: ctx.input, trigger: 'widgetRender', widgetSize: size };
            __result__[size] = fn(sizeCtx);
          } catch (e) {
            __result__[size] = null;
          }
        } else {
          __result__[size] = null;
        }
      }
      try {
        __loom_widget_result__ = JSON.stringify(__result__);
      } catch (e) {
        __loom_error__ = 'Widget serialisation failed: ' + (e && e.message ? e.message : String(e));
      }
    })();
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

        func runBundled(_ compiledJS: String) -> (result: String?, error: String?, entities: String?) {
            let bundled = bundle(compiledJS: compiledJS)
            guard let vm = JSVirtualMachine(), let ctx = JSContext(virtualMachine: vm) else {
                return (nil, "failed to create JSContext", nil)
            }
            var exception: String? = nil
            ctx.exceptionHandler = { _, ex in exception = ex?.toString() }

            ctx.evaluateScript("var ctx = { input: {}, trigger: 'manual', runId: 'selfcheck' };")
            ctx.evaluateScript("var __loom_result__ = undefined; var __loom_error__ = undefined; var __loom_entities_result__ = undefined;")
            ctx.evaluateScript(bundled)

            for _ in 0..<20 {
                ctx.evaluateScript(";")
                let done = ctx.evaluateScript("typeof __loom_result__ !== 'undefined' || typeof __loom_error__ !== 'undefined'")?.toBool() == true
                if done { break }
            }

            let result = ctx.evaluateScript("__loom_result__")
            let error = ctx.evaluateScript("__loom_error__")
            let entities = ctx.evaluateScript("__loom_entities_result__")
            return (
                result?.isUndefined == false ? result?.toString() : nil,
                error?.isUndefined == false ? error?.toString() : exception,
                entities?.isUndefined == false ? entities?.toString() : nil
            )
        }

        // No entities declared — must behave exactly as before entity collection was added.
        let plain = runBundled("""
        import { loom } from '@loom/core';
        export default loom(async (ctx) => {
          return { greeting: 'hi' };
        }, {
          name: 'Test',
          description: 'x',
        });
        """)
        check("plain.result", plain.result == "{\"greeting\":\"hi\"}")
        check("plain.noError", plain.error == nil)
        check("plain.noEntities", plain.entities == nil)

        // Entities declared — provider export runs and results are collected. Providers must
        // be `export const name = ...` (arrow/function expression), matching widget.ts's size
        // exports — esmToCJS's named-export handling only recognizes const/let/var
        // declarations, not `export function name() {}`.
        let withEntities = runBundled("""
        import { loom } from '@loom/core';
        export const noteProvider = function() {
          return [{ id: 'n1', title: 'Note One' }, { id: 'n2', title: 'Note Two' }];
        };
        export default loom(async (ctx) => {
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

        if failures.isEmpty {
            print("[ModuleBundler] self-check passed")
        } else {
            print("[ModuleBundler] self-check FAILED: \(failures.joined(separator: ", "))")
        }
        return failures.isEmpty
    }
    #endif
}
