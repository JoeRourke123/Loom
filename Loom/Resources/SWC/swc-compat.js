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

// ── Buffer ────────────────────────────────────────────────────────────────────
// Decode base64 → Uint8Array directly — no atob() needed.
var __loom_Buffer__ = {
  from: function(base64, encoding) {
    if (encoding !== 'base64') throw new Error('[swc-compat] Buffer.from: unsupported encoding: ' + encoding);
    var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    var lookup = new Uint8Array(128);
    for (var i = 0; i < 64; i++) lookup[chars.charCodeAt(i)] = i;
    var len = base64.length;
    while (len > 0 && base64[len - 1] === '=') len--;
    var out = new Uint8Array(Math.floor(len * 3 / 4));
    for (var i = 0, j = 0; i < len; ) {
      var a = lookup[base64.charCodeAt(i++)];
      var b = lookup[base64.charCodeAt(i++)];
      var c = i < len ? lookup[base64.charCodeAt(i++)] : 0;
      var d = i < len ? lookup[base64.charCodeAt(i++)] : 0;
      out[j++] = (a << 2) | (b >> 4);
      if (j < out.length) out[j++] = ((b & 0xF) << 4) | (c >> 2);
      if (j < out.length) out[j++] = ((c & 0x3) << 6) | d;
    }
    return out;
  }
};

// ── require() shim ────────────────────────────────────────────────────────────
var require = function(mod) {
  if (mod === 'util') return { TextDecoder: __loom_TextDecoder__, TextEncoder: __loom_TextEncoder__ };
  if (mod === 'node:buffer' || mod === 'buffer') return { Buffer: __loom_Buffer__ };
  throw new Error('[swc-compat] Unknown module: ' + mod);
};

// ── CommonJS module object ────────────────────────────────────────────────────
var module = { exports: {} };
var exports = module.exports;

// ── queueMicrotask (used by wasm-bindgen FinalizationRegistry path) ───────────
if (typeof queueMicrotask === 'undefined') {
  var queueMicrotask = function(fn) { fn(); };
}
