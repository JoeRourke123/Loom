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

        // Emits CommonJS: SWC itself resolves ESM→CJS, including re-exports and `export *`,
        // which the old line-oriented regex converter got wrong. Two of these are load-bearing:
        //
        //   externalHelpers: false — otherwise helpers arrive as
        //     require("@swc/helpers/_/_interop_require_default"), which ModuleBundler's require
        //     shim has no way to resolve. Inlined helpers are what we want. It is the default;
        //     pinned here because the failure is silent until runtime.
        //   target: es2022 — must stay >= es2017. Downleveling async/await drags in
        //     _async_to_generator and regenerator.
        //
        // strictMode: false drops the per-module "use strict" prologue. Concatenated into the
        // middle of a bundle it would be a dead string expression rather than a directive, so
        // the entry would run sloppy while factory bodies ran strict; off everywhere is
        // consistent and matches what ran before the compiler swap.
        let result = ctx.evaluateScript("""
        (function() {
          try {
            var r = __swc__.transformSync(__loom_src__, {
              isModule: true,
              jsc: {
                parser: { syntax: 'typescript', tsx: false },
                target: 'es2022',
                externalHelpers: false,
                loose: false
              },
              module: { type: 'commonjs', strictMode: false }
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
        try injectWasmBytes(ctx)
        try evalResource(ctx, name: "wasm", ext: "js", subdirectory: "SWC")
        ctx.evaluateScript("var __swc__ = module.exports;")
        if let ex = ctx.exception {
            ctx.exception = nil
            throw CompileError.swcError("SWC module init failed: \(ex.toString() ?? "unknown")")
        }
        compilerContext = ctx
        return ctx
    }

    /// Hands the wasm binary to swc-compat.js's require('fs') shim as `__loom_wasm_bytes__`.
    ///
    /// The binary is ~19 MB, so it is exposed as a Uint8Array over a single heap allocation
    /// rather than copied through a base64 string — that would mean a 25 MB Swift string, a
    /// 25 MB JS string and a decode pass, every one of which is avoidable. JSValue has no typed
    /// array API, hence the drop to the C API.
    private func injectWasmBytes(_ ctx: JSContext) throws {
        let url = Bundle.main.url(forResource: "wasm_bg", withExtension: "wasm", subdirectory: "SWC")
            ?? Bundle.main.url(forResource: "wasm_bg", withExtension: "wasm")
        guard let url else { throw CompileError.resourceMissing("wasm_bg.wasm") }
        let data = try Data(contentsOf: url)

        // NoCopy: JSC reads straight from this allocation for the life of the typed array, so it
        // must outlive the local Data. The deallocator frees it when JSC drops the last reference.
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: data.count, alignment: 1)
        data.copyBytes(to: buffer.assumingMemoryBound(to: UInt8.self), count: data.count)

        var exception: JSValueRef?
        let array = JSObjectMakeTypedArrayWithBytesNoCopy(
            ctx.jsGlobalContextRef,
            kJSTypedArrayTypeUint8Array,
            buffer,
            data.count,
            { pointer, _ in pointer?.deallocate() },
            nil,
            &exception
        )
        guard let array, exception == nil else {
            buffer.deallocate()
            throw CompileError.swcError("Failed to expose wasm_bg.wasm to JSC")
        }
        ctx.setObject(JSValue(jsValueRef: array, in: ctx), forKeyedSubscript: "__loom_wasm_bytes__" as NSString)
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
    // Carries the filename SWC can't: it reports line/column only, so a helper module's syntax
    // error would otherwise read as an error in main.ts.
    case moduleError(String)

    var errorDescription: String? {
        switch self {
        case .resourceMissing(let name): return "SWC resource not found: \(name)"
        case .swcError(let msg): return msg
        case .moduleError(let msg): return msg
        }
    }
}
