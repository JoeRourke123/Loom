// JSC compatibility shim — evaluated before wasm.js.
// Raw JSContext has no browser APIs (no atob, no fetch, no TextDecoder, etc.).
// Must use var so declarations survive across evaluateScript calls.

// ── TextDecoder / TextEncoder ─────────────────────────────────────────────────
// Use typeof to avoid ReferenceError on missing APIs and to avoid the
// "can't create duplicate variable that shadows a global property" error if
// a native version exists. Store in aliased vars so require() never references
// the bare name at call-time (which would hit TDZ from wasm.js's own `const`).

var __loom_TextDecoder__ = (typeof TextDecoder !== 'undefined') ? TextDecoder : function(encoding) {
  this.decode = function(bytes) {
    if (!bytes || bytes.length === 0) return '';
    var out = '', i = 0;
    while (i < bytes.length) {
      var b1 = bytes[i++];
      if (b1 < 0x80) { out += String.fromCharCode(b1); }
      else if (b1 < 0xE0) { out += String.fromCharCode(((b1 & 0x1F) << 6) | (bytes[i++] & 0x3F)); }
      else if (b1 < 0xF0) { var b2 = bytes[i++] & 0x3F, b3 = bytes[i++] & 0x3F; out += String.fromCharCode(((b1 & 0x0F) << 12) | (b2 << 6) | b3); }
      else { var b2 = bytes[i++] & 0x3F, b3 = bytes[i++] & 0x3F, b4 = bytes[i++] & 0x3F; var cp = (((b1 & 0x07) << 18) | (b2 << 12) | (b3 << 6) | b4) - 0x10000; out += String.fromCharCode(0xD800 + (cp >> 10), 0xDC00 + (cp & 0x3FF)); }
    }
    return out;
  };
};

var __loom_TextEncoder__ = (typeof TextEncoder !== 'undefined') ? TextEncoder : function() {
  this.encode = function(str) {
    var bytes = [], i = 0;
    while (i < str.length) {
      var c = str.charCodeAt(i++);
      if (c < 0x80) { bytes.push(c); }
      else if (c < 0x800) { bytes.push(0xC0 | (c >> 6), 0x80 | (c & 0x3F)); }
      else if (c >= 0xD800 && c <= 0xDBFF) { var n = str.charCodeAt(i++); var cp = 0x10000 + ((c - 0xD800) << 10) + (n - 0xDC00); bytes.push(0xF0|(cp>>18), 0x80|((cp>>12)&0x3F), 0x80|((cp>>6)&0x3F), 0x80|(cp&0x3F)); }
      else { bytes.push(0xE0|(c>>12), 0x80|((c>>6)&0x3F), 0x80|(c&0x3F)); }
    }
    return new Uint8Array(bytes);
  };
};

// ── fs / path (wasm binary loading) ───────────────────────────────────────────
// @swc/wasm ships the 19 MB binary as a separate wasm_bg.wasm and its glue loads it with
//   const path = require('path').join(__dirname, 'wasm_bg.wasm');
//   const bytes = require('fs').readFileSync(path);
// SWCCompiler defines __loom_wasm_bytes__ (a Uint8Array over the bundled resource, made
// without copying) before evaluating wasm.js, so readFileSync just hands that back and the
// filename never matters. @swc/wasm-typescript used to inline the binary as base64, which
// is why this shim previously carried a hand-rolled Buffer.from decoder instead.
var __dirname = '';

// ── require() shim ────────────────────────────────────────────────────────────
var require = function(mod) {
  if (mod === 'util') return { TextDecoder: __loom_TextDecoder__, TextEncoder: __loom_TextEncoder__ };
  if (mod === 'path') return { join: function() { return 'wasm_bg.wasm'; } };
  if (mod === 'fs') return {
    readFileSync: function() {
      if (typeof __loom_wasm_bytes__ === 'undefined') {
        throw new Error('[swc-compat] __loom_wasm_bytes__ not set — SWCCompiler must define it before evaluating wasm.js');
      }
      return __loom_wasm_bytes__;
    }
  };
  throw new Error('[swc-compat] Unknown module: ' + mod);
};

// ── CommonJS module object ────────────────────────────────────────────────────
var module = { exports: {} };
var exports = module.exports;

// ── queueMicrotask (used by wasm-bindgen FinalizationRegistry path) ───────────
if (typeof queueMicrotask === 'undefined') {
  var queueMicrotask = function(fn) { fn(); };
}
