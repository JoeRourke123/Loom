import Foundation

enum ModuleBundler {
    // Takes SWC-compiled CommonJS output and returns a self-contained JS string.
    // Resolves vendor requires by prepending pre-bundled IIFEs.
    // Injects @loom/core stub and a require() shim.
    static func bundle(compiledJS: String) -> String {
        let requiredVendors = detectVendors(in: compiledJS)
        var parts: [String] = []

        // CommonJS environment
        parts.append(commonJSSetup)

        // @loom/core stub
        parts.append(loomCoreStub)

        // Pre-bundled vendor IIFEs + require entries
        var requireEntries: [String] = []
        for pkg in requiredVendors {
            if let iife = pkg.jsContent() {
                parts.append(iife)
                requireEntries.append("'\(pkg.rawValue)': \(pkg.globalName)")
            }
        }

        // require() shim
        parts.append(requireShim(entries: requireEntries))

        // The compiled script
        parts.append(compiledJS)

        // Run default export with ctx and capture result
        parts.append(executionFooter)

        return parts.joined(separator: "\n;\n")
    }

    private static func detectVendors(in js: String) -> [VendorPackage] {
        // Match require('pkg') or require("pkg")
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
