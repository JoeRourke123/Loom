// JSC compatibility shim — evaluated before wasm.js.
// Provides Node.js globals that wasm-bindgen generated code expects.
// Must use var (not const/let) so declarations survive across evaluateScript calls.

var require = function(mod) {
  if (mod === 'util') {
    return { TextDecoder: TextDecoder, TextEncoder: TextEncoder };
  }
  if (mod === 'node:buffer' || mod === 'buffer') {
    return { Buffer: __loom_Buffer__ };
  }
  throw new Error('[swc-compat] Unknown module: ' + mod);
};

var __loom_Buffer__ = {
  from: function(data, encoding) {
    if (encoding === 'base64') {
      var binary = atob(data);
      var bytes = new Uint8Array(binary.length);
      for (var i = 0; i < binary.length; i++) {
        bytes[i] = binary.charCodeAt(i);
      }
      return bytes;
    }
    throw new Error('[swc-compat] Buffer.from: unsupported encoding: ' + encoding);
  }
};

var module = { exports: {} };
var exports = module.exports;

// JSC may not have queueMicrotask; wasm.js uses it for finalizers (non-critical).
if (typeof queueMicrotask === 'undefined') {
  var queueMicrotask = function(fn) { fn(); };
}

// JSC has TextDecoder/TextEncoder as globals on iOS 14+ — no stub needed.
// FinalizationRegistry: wasm.js already guards with typeof check, no stub needed.
