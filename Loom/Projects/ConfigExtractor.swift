import Foundation
import JavaScriptCore

// Statically extracts LoomConfig from a main.ts source file's `loom(handler, config)` call,
// without ever invoking the handler. See ADR-007 for why this evaluates the config literal
// in an isolated JSContext rather than parsing a real AST (none is vendored — SWC's WASM
// binding here only exposes transformSync, never parseSync) or regex-matching it (Zod's
// chainable builder grammar is recursive, unlike the line-scoped import/export syntax
// ModuleBundler.esmToCJS gets away with regex-matching).
enum ConfigExtractor {

    // MARK: - Public API

    // Falls back to a name-only config on any failure (missing loom() call, non-literal
    // config, extraction error) so callers never special-case "no config yet".
    nonisolated static func extract(for project: LoomProject) -> LoomConfig {
        guard let source = try? String(contentsOf: project.mainFileURL, encoding: .utf8) else {
            return LoomConfig(name: project.name, description: "")
        }
        return extract(source: source, fallbackName: project.name)
    }

    nonisolated static func extract(source: String, fallbackName: String) -> LoomConfig {
        guard let configSource = sliceConfigSource(from: source),
              let json = evaluateAndNormalize(configSource: configSource),
              let data = json.data(using: .utf8),
              let config = try? JSONDecoder().decode(LoomConfig.self, from: data)
        else {
            return LoomConfig(name: fallbackName, description: "")
        }
        return config
    }

    /// Non-nil when a config literal was found but could not be evaluated, in which case
    /// `extract` has silently fallen back to name-only — permissions, intent inputs, entities,
    /// health scopes, widget config and ai provider all quietly absent.
    ///
    /// The usual cause is the config referencing a binding rather than being self-contained;
    /// it is evaluated in a throwaway context with only `z` defined, so anything else is a
    /// ReferenceError. Multi-file imports make this much easier to hit — moving constants into
    /// a helper and referencing them from `loom()` is an obvious thing to try, and it silently
    /// strips the script's whole configuration.
    ///
    /// Separate function rather than a changed `extract` signature so none of its seven call
    /// sites have to move.
    nonisolated static func configDiagnostic(for project: LoomProject) -> String? {
        guard let source = try? String(contentsOf: project.mainFileURL, encoding: .utf8),
              let configSource = sliceConfigSource(from: source)
        else { return nil }
        guard evaluateAndNormalize(configSource: configSource) == nil else { return nil }
        return "Config could not be read, so only the project name is in effect — permissions, intent, entities and widget settings are being ignored. The loom() config must be a self-contained literal: it cannot reference imported or outer variables."
    }

    // MARK: - Slicing

    // Finds the `loom(` call outside any string/comment and returns the exact source text of
    // its 2nd argument — the config object literal. Tracks paren/brace/bracket depth through
    // the 1st argument (the handler) to find the correct top-level comma; the handler's
    // contents are scanned only for depth-balancing, never semantically inspected.
    nonisolated static func sliceConfigSource(from source: String) -> String? {
        let chars = Array(source)
        guard let callStart = findLoomCallStart(in: chars) else { return nil }

        var i = callStart
        var parenDepth = 1   // already past the opening '(' of loom(
        var braceDepth = 0
        var bracketDepth = 0
        var configStart: Int? = nil

        while i < chars.count {
            let c = chars[i]

            if let skipTo = skipCommentOrString(chars, from: i) {
                i = skipTo
                continue
            }

            switch c {
            case "(":
                parenDepth += 1
            case ")":
                parenDepth -= 1
                if parenDepth == 0 {
                    guard let start = configStart else { return nil }
                    return String(chars[start..<i]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            case "{":
                braceDepth += 1
            case "}":
                braceDepth -= 1
            case "[":
                bracketDepth += 1
            case "]":
                bracketDepth -= 1
            case ",":
                if configStart == nil, parenDepth == 1, braceDepth == 0, bracketDepth == 0 {
                    configStart = i + 1
                }
            default:
                break
            }
            i += 1
        }
        return nil
    }

    nonisolated private static func findLoomCallStart(in chars: [Character]) -> Int? {
        var i = 0
        while i < chars.count {
            if let skipTo = skipCommentOrString(chars, from: i) {
                i = skipTo
                continue
            }
            if chars[i] == "l", chars[i...].starts(with: "loom(") {
                let precededByWordChar = i > 0 && (chars[i - 1].isLetter || chars[i - 1].isNumber || chars[i - 1] == "_")
                if !precededByWordChar {
                    return i + "loom(".count
                }
            }
            i += 1
        }
        return nil
    }

    // If `chars[i]` starts a line comment, block comment, or string/template literal, returns
    // the index just past it (contents are opaque — never inspected). Otherwise nil.
    nonisolated private static func skipCommentOrString(_ chars: [Character], from i: Int) -> Int? {
        let c = chars[i]
        if c == "/", i + 1 < chars.count, chars[i + 1] == "/" {
            var j = i
            while j < chars.count, chars[j] != "\n" { j += 1 }
            return j
        }
        if c == "/", i + 1 < chars.count, chars[i + 1] == "*" {
            var j = i + 2
            while j + 1 < chars.count, !(chars[j] == "*" && chars[j + 1] == "/") { j += 1 }
            return min(j + 2, chars.count)
        }
        if c == "\"" || c == "'" || c == "`" {
            let quote = c
            var j = i + 1
            while j < chars.count, chars[j] != quote {
                j += (chars[j] == "\\") ? 2 : 1
            }
            return min(j + 1, chars.count)
        }
        return nil
    }

    // MARK: - Evaluation

    // Evaluates the sliced config literal in a fresh, Loom-free JSContext (zod preloaded so
    // `z.object(...)` resolves) and normalizes it to a JSON string matching LoomConfig's shape.
    // No Loom global is injected — even a spec-violating literal has no bridge surface to abuse.
    nonisolated private static func evaluateAndNormalize(configSource: String) -> String? {
        guard let vm = JSVirtualMachine(), let ctx = JSContext(virtualMachine: vm),
              let zodJS = VendorPackage.zod.jsContent()
        else { return nil }

        var caughtException: String? = nil
        ctx.exceptionHandler = { _, exception in
            caughtException = exception?.toString()
        }

        ctx.evaluateScript(zodJS)
        ctx.evaluateScript("var z = \(VendorPackage.zod.globalName).z;")
        ctx.evaluateScript(normalizerJS)
        ctx.evaluateScript("var __loom_extracted_config__ = (\(configSource));")
        ctx.evaluateScript("""
        var __loom_extract_result__ = null;
        try {
          __loom_extract_result__ = JSON.stringify(__loom_normalize_config__(__loom_extracted_config__));
        } catch (e) {
          __loom_extract_result__ = null;
        }
        """)

        if caughtException != nil { return nil }

        guard let result = ctx.evaluateScript("__loom_extract_result__"),
              !result.isNull, !result.isUndefined,
              let str = result.toString()
        else { return nil }
        return str
    }

    // Walks a plain config object (and, for intent.inputs, a Zod object schema via its
    // internal `_zod.def` — Zod v4's marker, confirmed against the vendored zod.js) into a
    // JSON-serialisable mirror of LoomConfig. Every field is defensively guarded so a
    // partially-shaped or missing config still normalizes to something decodable.
    private static let normalizerJS = """
    function __loom_walk_zod_object__(schema) {
      var shape = (schema && typeof schema.shape === 'object') ? schema.shape : {};
      var result = [];
      for (var key in shape) {
        var fieldSchema = shape[key];
        var optional = false;
        var inner = fieldSchema;
        if (inner && inner._zod && inner._zod.def && inner._zod.def.type === 'optional') {
          optional = true;
          inner = inner._zod.def.innerType;
        }
        var zType = (inner && inner._zod && inner._zod.def) ? inner._zod.def.type : 'string';
        var type = 'string';
        if (zType === 'number') type = 'number';
        else if (zType === 'boolean') type = 'boolean';
        else if (zType === 'date') type = 'date';
        var description = (fieldSchema && fieldSchema.description) || (inner && inner.description) || null;
        result.push({ name: key, type: type, description: description, optional: optional });
      }
      return result;
    }

    function __loom_normalize_config__(config) {
      var out = {};
      out.name = (config && typeof config.name === 'string') ? config.name : '';
      out.description = (config && typeof config.description === 'string') ? config.description : '';
      out.permissions = (config && Array.isArray(config.permissions)) ? config.permissions : [];
      out.returnsResult = !!(config && config.returnsResult);
      out.triggers = {
        backgroundRefresh: !!(config && config.triggers && config.triggers.backgroundRefresh),
        backgroundProcessing: !!(config && config.triggers && config.triggers.backgroundProcessing)
      };
      if (config && config.intent && config.intent.inputs) {
        out.intent = { inputs: __loom_walk_zod_object__(config.intent.inputs) };
      }
      if (config && config.entities && typeof config.entities === 'object') {
        var entities = {};
        for (var typeName in config.entities) {
          var e = config.entities[typeName] || {};
          var fields = {};
          if (e.fields && typeof e.fields === 'object') {
            for (var fieldName in e.fields) {
              var f = e.fields[fieldName] || {};
              fields[fieldName] = { type: f.type || 'string', optional: !!f.optional };
            }
          }
          entities[typeName] = {
            displayName: e.displayName || typeName,
            fields: fields,
            provider: e.provider || ''
          };
        }
        out.entities = entities;
      }
      if (config && config.health) {
        out.health = {
          read: Array.isArray(config.health.read) ? config.health.read : [],
          write: Array.isArray(config.health.write) ? config.health.write : []
        };
      }
      if (config && config.widget) {
        out.widget = {
          refreshAfter: (typeof config.widget.refreshAfter === 'number') ? config.widget.refreshAfter : null,
          runOnTap: config.widget.runOnTap === true
        };
      }
      if (config && config.ai) {
        out.ai = { provider: (config.ai.provider && typeof config.ai.provider === 'string') ? config.ai.provider : 'auto' };
      }
      return out;
    }
    """

    // MARK: - Self-check

    // Ad-hoc regression guard for the slicer + Zod walk — no test target exists in this
    // project, so this is callable directly (e.g. from a debug build) rather than via XCTest.
    #if DEBUG
    @discardableResult
    static func runSelfCheck() -> Bool {
        var failures: [String] = []
        func check(_ name: String, _ condition: @autoclosure () -> Bool) {
            if !condition() { failures.append(name) }
        }

        // Basic literal.
        let basic = extract(source: """
        import { loom } from '@loom/core';
        export default loom(async (ctx) => {
          console.log('hi');
        }, {
          name: 'Test',
          description: 'A test project.',
        });
        """, fallbackName: "fallback")
        check("basic.name", basic.name == "Test")
        check("basic.description", basic.description == "A test project.")

        // Handler body with braces/parens/strings/comments that could fool a naive scanner.
        let tricky = extract(source: #"""
        import { loom } from '@loom/core';
        export default loom(async (ctx) => {
          // a comment with a } fake brace and a ) fake paren
          const s = "a string with ) fake paren and , fake comma and { fake brace";
          const t = `template with ${1 + 1} interpolation and } fake brace`;
          if (ctx.input.x) { return { a: 1, b: [1, 2, 3] }; }
        }, {
          name: 'Handler',
          description: 'Has a tricky handler body.',
          permissions: ['network', 'location'],
        });
        """#, fallbackName: "fallback")
        check("tricky.name", tricky.name == "Handler")
        check("tricky.permissions", tricky.permissions == ["network", "location"])

        // Nested template literals before the loom() call. skipCommentOrString scans a backtick
        // to the *next* backtick with no ${} awareness, so a nested html`` is not truly opaque —
        // it survives only because the backticks pair up and the gap between them stays
        // brace-balanced. Every web-sheet template and doc example is shaped exactly like this,
        // and a slice failure is silent (config falls back to an empty description), so pin it.
        let nestedTemplates = extract(source: #"""
        import { loom, html } from '@loom/core';
        function list(rows) {
          if (!rows.length) return html`<p class="empty">None</p>`;
          return html`<ul>${rows.map(r => html`
            <li>
              <span class="${r.done ? 'done' : ''}">${r.title}</span>
              <button hx-delete="/task?id=${r.id}" hx-target="#list">x</button>
            </li>`)}</ul>`;
        }
        export default loom(async (ctx) => {
          await Loom.ui.web({ template: 'index.html', routes: { '/tasks': () => list([]) } });
        }, {
          name: 'Nested',
          description: 'Nested template literals ahead of the call.',
        });
        """#, fallbackName: "fallback")
        check("nestedTemplates.name", nestedTemplates.name == "Nested")
        check("nestedTemplates.description", nestedTemplates.description == "Nested template literals ahead of the call.")

        // Zod intent.inputs — mixed types, .optional(), .describe() in both orders.
        let rich = extract(source: """
        import { loom } from '@loom/core';
        import { z } from 'zod';
        export default loom(async (ctx) => {}, {
          name: 'Rich',
          description: 'x',
          returnsResult: true,
          intent: {
            inputs: z.object({
              city: z.string().describe('City name'),
              count: z.number().optional(),
              alsoDescribed: z.boolean().optional().describe('described after optional'),
            }),
          },
        });
        """, fallbackName: "fallback")
        check("rich.returnsResult", rich.returnsResult == true)
        let params = rich.intent?.inputs ?? []
        check("rich.paramCount", params.count == 3)
        check("rich.city", params.first { $0.name == "city" }.map { $0.type == .string && $0.description == "City name" && !$0.optional } == true)
        check("rich.count", params.first { $0.name == "count" }.map { $0.type == .number && $0.optional } == true)
        check("rich.alsoDescribed", params.first { $0.name == "alsoDescribed" }.map { $0.description == "described after optional" } == true)

        // Malformed / missing loom() call — must fall back cleanly, not crash.
        let missing = extract(source: "const x = 1;", fallbackName: "Fallback Name")
        check("missing.fallback", missing.name == "Fallback Name" && missing.description == "")

        if failures.isEmpty {
            print("[ConfigExtractor] self-check passed")
        } else {
            print("[ConfigExtractor] self-check FAILED: \(failures.joined(separator: ", "))")
        }
        return failures.isEmpty
    }
    #endif
}
