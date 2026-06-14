import Foundation

enum ModuleBundler {
    // Takes SWC-stripped ESM output and returns a self-contained JS string for JSC.
    // Converts ESM import/export to CJS, prepends vendor IIFEs, injects require() shim.
    static func bundle(compiledJS: String) -> String {
        let cjsScript = esmToCJS(compiledJS)
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

        parts.append(requireShim(entries: requireEntries))
        parts.append(cjsScript)
        parts.append(executionFooter)

        return parts.joined(separator: "\n;\n")
    }

    // Convert single-line ESM import/export statements to CJS equivalents.
    // Handles the patterns produced by @swc/wasm-typescript strip-only output.
    private static func esmToCJS(_ esm: String) -> String {
        var counter = 0
        var output: [String] = []

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

            // import 'pkg' — side-effect import, skip
            if capture(trimmed, pattern: #"^import\s+['"][^'"]+['"]"#) != nil {
                continue
            }

            // export default <expr...>
            if trimmed.hasPrefix("export default ") {
                output.append("module.exports.default = " + trimmed.dropFirst("export default ".count))
                continue
            }

            // export { a, b } — values already in scope, no-op for single-script use
            if capture(trimmed, pattern: #"^export\s+\{"#) != nil {
                continue
            }

            output.append(line)
        }

        return output.joined(separator: "\n")
    }

    // Returns capture groups [fullMatch, group1, group2, ...] or nil if no match.
    private static func capture(_ s: String, pattern: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s))
        else { return nil }
        return (0..<m.numberOfRanges).map { i in
            guard let r = Range(m.range(at: i), in: s) else { return "" }
            return String(s[r])
        }
    }

    // Split comma-separated named import list, trimming whitespace.
    private static func splitNames(_ s: String) -> [String] {
        s.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    // Emit a var declaration for one named import, handling "foo as bar" aliases.
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

    private static let commonJSSetup = """
    var module = { exports: {} };
    var exports = module.exports;
    """

    private static let loomCoreStub = """
    var __loom_core__ = {
      loom: function(handler, config) { return handler; }
    };
    """

    private static func requireShim(entries: [String]) -> String {
        let vendorMap = entries.isEmpty ? "" : entries.joined(separator: ",\n  ")
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
}
