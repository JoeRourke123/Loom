import Foundation
import JavaScriptCore

actor SWCCompiler {
    static let shared = SWCCompiler()
    private var compilerContext: JSContext?
    private init() {}

    func compile(_ source: String) throws -> String {
        let ctx = try loadedContext()

        ctx.setObject(source, forKeyedSubscript: "__loom_src__" as NSString)
        ctx.exception = nil

        // @swc/wasm-typescript options: module (boolean) and mode only — no CJS output.
        // strip-only removes TS types and leaves ESM intact; ModuleBundler converts ESM→CJS.
        let result = ctx.evaluateScript("""
        (function() {
          try {
            var r = __swc__.transformSync(__loom_src__, {
              module: true,
              mode: 'strip-only'
            });
            return { ok: true, code: r ? r.code : null };
          } catch(e) {
            return { ok: false, error: e && e.message ? e.message : String(e) };
          }
        })()
        """)

        if let ex = ctx.exception {
            ctx.exception = nil
            throw CompileError.swcError(ex.toString() ?? "SWC evaluation error")
        }
        guard let result, !result.isNull, !result.isUndefined else {
            throw CompileError.swcError("SWC returned no result")
        }
        let ok = result.objectForKeyedSubscript("ok")?.toBool() ?? false
        if !ok {
            let msg = result.objectForKeyedSubscript("error")?.toString() ?? "Unknown SWC error"
            throw CompileError.swcError(msg)
        }
        guard let code = result.objectForKeyedSubscript("code")?.toString(),
              !result.objectForKeyedSubscript("code")!.isNull else {
            throw CompileError.swcError("SWC produced no output code")
        }
        return code
    }

    private func loadedContext() throws -> JSContext {
        if let ctx = compilerContext { return ctx }
        let ctx = JSContext()!
        // Do NOT set exceptionHandler — it clears ctx.exception, which we need for error detection.
        try evalResource(ctx, name: "swc-compat", ext: "js", subdirectory: "SWC")
        try evalResource(ctx, name: "wasm", ext: "js", subdirectory: "SWC")
        ctx.evaluateScript("var __swc__ = module.exports;")
        if let ex = ctx.exception {
            ctx.exception = nil
            throw CompileError.swcError("SWC module init failed: \(ex.toString() ?? "unknown")")
        }
        compilerContext = ctx
        return ctx
    }

    private func evalResource(_ ctx: JSContext, name: String, ext: String, subdirectory: String) throws {
        let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: subdirectory)
            ?? Bundle.main.url(forResource: name, withExtension: ext)
        guard let url else { throw CompileError.resourceMissing("\(name).\(ext)") }
        let source = try String(contentsOf: url, encoding: .utf8)
        ctx.evaluateScript(source)
        if let ex = ctx.exception {
            let msg = ex.toString() ?? "unknown"
            ctx.exception = nil
            throw CompileError.swcError("Error loading \(name).\(ext): \(msg)")
        }
    }
}

enum CompileError: Error, LocalizedError {
    case resourceMissing(String)
    case swcError(String)

    var errorDescription: String? {
        switch self {
        case .resourceMissing(let name): return "SWC resource not found: \(name)"
        case .swcError(let msg): return msg
        }
    }
}
