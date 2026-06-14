import Foundation
import JavaScriptCore

actor SWCCompiler {
    static let shared = SWCCompiler()

    private var compilerContext: JSContext?

    private init() {}

    func compile(_ source: String) throws -> String {
        let ctx = try loadedContext()
        let opts = """
        {
          "jsc": { "parser": { "syntax": "typescript" } },
          "module": { "type": "commonjs" }
        }
        """
        guard
            let swc = ctx.objectForKeyedSubscript("__swc__"),
            let result = swc.invokeMethod("transformSync", withArguments: [source, opts]),
            !result.isUndefined,
            !result.isNull
        else {
            if let ex = ctx.exception { throw CompileError.swcError(ex.toString() ?? "unknown") }
            throw CompileError.swcError("transformSync returned nil")
        }
        if let ex = ctx.exception { throw CompileError.swcError(ex.toString() ?? "unknown") }
        guard let code = result.objectForKeyedSubscript("code")?.toString() else {
            throw CompileError.swcError("No 'code' in transformSync result")
        }
        return code
    }

    private func loadedContext() throws -> JSContext {
        if let ctx = compilerContext { return ctx }
        let ctx = JSContext()!
        ctx.exceptionHandler = { _, ex in
            print("[SWCCompiler] JSC exception: \(ex?.toString() ?? "nil")")
        }
        try evalResource(ctx, name: "swc-compat", ext: "js", subdirectory: "SWC")
        try evalResource(ctx, name: "wasm", ext: "js", subdirectory: "SWC")
        ctx.evaluateScript("var __swc__ = module.exports;")
        compilerContext = ctx
        return ctx
    }

    private func evalResource(_ ctx: JSContext, name: String, ext: String, subdirectory: String) throws {
        // Try with subdirectory first, then fall back to bundle root.
        let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: subdirectory)
            ?? Bundle.main.url(forResource: name, withExtension: ext)
        guard let url else { throw CompileError.resourceMissing("\(name).\(ext)") }
        let source = try String(contentsOf: url, encoding: .utf8)
        ctx.evaluateScript(source)
        if let ex = ctx.exception {
            throw CompileError.swcError("Loading \(name).\(ext): \(ex.toString() ?? "")")
        }
    }
}

enum CompileError: Error, LocalizedError {
    case resourceMissing(String)
    case swcError(String)

    var errorDescription: String? {
        switch self {
        case .resourceMissing(let name): return "SWC resource not found in bundle: \(name)"
        case .swcError(let msg): return msg
        }
    }
}
