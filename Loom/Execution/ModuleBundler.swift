import Foundation

enum ModuleBundler {

    // MARK: - Public API

    // Bundles a main.ts SWC-compiled ESM string into a self-contained JSC payload.
    static func bundle(compiledJS: String) -> String {
        let cjsScript = esmToCJS(compiledJS, collectExports: false).script
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
          try { __loom_result__ = JSON.stringify(r !== undefined ? r : null); }
          catch(e) { __loom_result__ = 'null'; }
        })
        .catch(function(e) {
          __loom_error__ = e && e.message ? e.message : String(e);
        });
    })();
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
}
